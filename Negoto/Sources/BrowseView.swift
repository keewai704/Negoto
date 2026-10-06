import NegotoCore
import SwiftUI

struct BrowseRow: Identifiable, Hashable {
    var id: Int64
    var noteID: Int64
    var front: String
    var deck: String
    var due: String
    var interval: String
    var queue: Int
    var flag: Int
}

/// Loads rows for a search (Anki syntax) — shared by Browse and Search.
@MainActor
enum BrowseLoader {
    static let pageLimit = 1000

    static func load(_ col: AnkiCollection, query: String, order: BrowseOrder, limit: Int = pageLimit) -> (rows: [BrowseRow], total: Int) {
        let s = col.search(query)
        let from = "FROM cards c JOIN notes n ON n.id = c.nid WHERE \(s.whereClause)"
        let total = (try? col.db.scalar("SELECT count() " + from, s.arguments).int) ?? 0
        let today = col.timingToday().daysElapsed
        let result = (try? col.db.query("SELECT c.id, n.id, n.sfld, n.flds, n.mid, c.ord, c.queue, c.due, c.ivl, c.did, c.flags, c.odid \(from) ORDER BY \(order.sql) LIMIT \(limit)",
                                        s.arguments)) ?? []
        let rows = result.map { r -> BrowseRow in
            let nt = col.notetypes[r[4].int64]
            let fields = Note.splitFields(r[3].string)
            let sortIdx = nt?.sortFieldIndex ?? 0
            let raw = sortIdx < fields.count ? fields[sortIdx] : r[2].string
            var text = HTMLText.strip(raw.replacingOccurrences(of: "<br>", with: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
            if nt?.isCloze == true { text = Cloze.render(text, ord: r[5].int + 1, question: false) }
            let queue = r[6].int
            let due: String
            switch queue {
            case -1: due = "保留中"
            case -2, -3: due = "延期中"
            case 0: due = "新規"
            case 1: due = "今日"
            default: due = Format.daysFromNow(r[7].int - today)
            }
            let deckID = r[11].int64 != 0 ? r[11].int64 : r[9].int64
            return BrowseRow(id: r[0].int64, noteID: r[1].int64, front: String(HTMLText.strip(text).prefix(160)),
                             deck: col.decks[deckID]?.baseName ?? "", due: due,
                             interval: r[8].int > 0 ? Format.interval(days: r[8].int) : "–",
                             queue: queue, flag: r[10].int & 7)
        }
        return (rows, total)
    }
}

enum BrowseOrder: String, CaseIterable, Identifiable {
    case created, sortField, due, interval
    var id: String { rawValue }
    var title: String {
        switch self {
        case .created: return "追加順"
        case .sortField: return "表面"
        case .due: return "期日"
        case .interval: return "間隔"
        }
    }
    var sql: String {
        switch self {
        case .created: return "n.id DESC, c.ord"
        case .sortField: return "n.sfld COLLATE NOCASE, c.ord"
        case .due: return "c.type = 0, c.queue < 0, c.due, c.id"
        case .interval: return "c.ivl DESC, c.id"
        }
    }
}

/// Browse: Anki search syntax with filter menus. Compact widths show a list (tap to edit, "選択" for
/// several cards); regular widths show a table with the selected note's editor in an inspector.
struct BrowseScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var rows: [BrowseRow] = []
    @State private var total = 0
    @State private var selection = Set<Int64>()
    @State private var editMode = EditMode.inactive
    @State private var showInspector = true
    @State private var pendingDelete: Set<Int64>?
    @AppStorage("browseOrder") private var order: BrowseOrder = .created

    var body: some View {
        @Bindable var model = model
        Group {
            if hSize == .regular { table } else { list }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                FilterChips(query: $model.browseQuery, order: $order)
                Text(countText).font(.footnote.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 20)
            }
            .padding(.vertical, 6)
            .background(hSize == .regular ? Color(uiColor: .systemBackground) : Theme.background)
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(model.browseQuery.isEmpty ? "カードがありません" : "見つかりません",
                                       systemImage: "magnifyingglass",
                                       description: Text("例: deck:\"英単語\" is:due tag:頻出 -is:suspended"))
            }
        }
        .searchable(text: $model.browseQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "検索（Ankiの検索式が使えます）")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("ブラウズ")
        .navigationDestination(for: BrowseRow.self) { row in
            BrowseEditorPane(cardID: row.id, noteID: row.noteID)
        }
        .confirmationDialog("\(pendingNoteCount)件のノートを削除しますか？",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let ids = pendingDelete { CardActions.deleteNotes(of: ids, model: self.model) }
                selection = []
                editMode = .inactive
            }
        } message: {
            Text("ノートのすべてのカードと学習の進み具合が削除されます。")
        }
        .task(id: LoadKey(query: model.browseQuery, order: order, revision: model.revision)) {
            if !model.browseQuery.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            load()
        }
    }

    private var countText: String {
        var s = total > rows.count ? "\(Format.number(total))枚中 \(Format.number(rows.count))枚を表示" : "\(Format.number(total))枚"
        if !selection.isEmpty && (hSize == .regular || editMode.isEditing) { s += "・\(selection.count)枚を選択中" }
        return s
    }

    private var pendingNoteCount: Int {
        guard let ids = pendingDelete else { return 0 }
        return Set(rows.filter { ids.contains($0.id) }.map(\.noteID)).count
    }

    struct LoadKey: Equatable {
        var query: String
        var order: BrowseOrder
        var revision: Int
    }

    private func load() {
        guard let col = model.collectionHandle else { return }
        let result = BrowseLoader.load(col, query: model.browseQuery, order: order)
        rows = result.rows
        total = result.total
        selection = selection.filter { id in rows.contains { $0.id == id } }
    }

    // MARK: Compact: list

    private var list: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                NavigationLink(value: row) { BrowseRowView(row: row) }
                    .contextMenu {
                        CardActionsMenu(ids: [row.id]) { pendingDelete = $0 }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = [row.id] } label: { Label("削除", systemImage: "trash") }
                        Button { CardActions.toggleSuspend([row.id], model: model) } label: {
                            Label(row.queue == -1 ? "保留を解除" : "保留", systemImage: row.queue == -1 ? "play.circle" : "pause.circle")
                        }
                        .tint(.orange)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if editMode.isEditing {
                    CardActionsMenu(ids: selection, label: true) { pendingDelete = $0 }
                        .disabled(selection.isEmpty)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "完了" : "選択") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                        if !editMode.isEditing { selection = [] }
                    }
                }
                .fontWeight(editMode.isEditing ? .semibold : .regular)
                if !editMode.isEditing {
                    Button { model.editorRequest = .add(deckID: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("カードを追加")
                }
            }
        }
    }

    // MARK: Regular: table + inspector

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("表面") { row in
                HStack(spacing: 6) {
                    Text(row.front.isEmpty ? "（空）" : row.front).lineLimit(1)
                    if row.flag > 0 { Image(systemName: "flag.fill").font(.caption).foregroundStyle(FlagInfo.color(row.flag)) }
                }
                .opacity(row.queue < 0 ? 0.5 : 1)
            }
            TableColumn("デッキ") { row in Text(row.deck).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 80, ideal: 130)
            TableColumn("期日") { row in Text(row.due).foregroundStyle(.secondary).monospacedDigit() }
                .width(min: 60, ideal: 76)
            TableColumn("間隔") { row in Text(row.interval).foregroundStyle(.secondary).monospacedDigit() }
                .width(min: 50, ideal: 70)
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            CardActionsMenu(ids: ids) { pendingDelete = $0 }
        } primaryAction: { _ in
            showInspector = true
        }
        .inspector(isPresented: $showInspector) {
            inspector
                .inspectorColumnWidth(min: 320, ideal: 380, max: 460)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                CardActionsMenu(ids: selection, label: true) { pendingDelete = $0 }
                    .disabled(selection.isEmpty)
                Button { model.editorRequest = .add(deckID: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("カードを追加")
                Button { showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                    .accessibilityLabel(showInspector ? "エディタを隠す" : "エディタを表示")
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if selection.count == 1, let row = rows.first(where: { selection.contains($0.id) }) {
            BrowseEditorPane(cardID: row.id, noteID: row.noteID)
                .id(row.noteID)
        } else {
            ContentUnavailableView(selection.isEmpty ? "カードを選択" : "\(selection.count)枚を選択中",
                                   systemImage: selection.isEmpty ? "rectangle.and.pencil.and.ellipsis" : "checklist",
                                   description: Text(selection.isEmpty ? "選んだカードのノートをここで編集できます。" : "「操作」メニューでまとめて変更できます。"))
        }
    }
}

struct BrowseRowView: View {
    var row: BrowseRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.front.isEmpty ? "（空）" : row.front).lineLimit(2)
                if row.flag > 0 { Image(systemName: "flag.fill").font(.caption).foregroundStyle(FlagInfo.color(row.flag)) }
            }
            Text("\(row.deck)・\(row.due)・\(row.interval)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
        .opacity(row.queue < 0 ? 0.5 : 1)
        .padding(.vertical, 2)
    }
}

/// Changes to a set of cards (suspend, flag, move, delete).
@MainActor
enum CardActions {
    static func cards(_ ids: Set<Int64>, _ col: AnkiCollection) -> [Card] { ids.compactMap { try? col.card(id: $0) } }

    static func toggleSuspend(_ ids: Set<Int64>, model: AppModel) {
        guard let col = model.collectionHandle else { return }
        let list = cards(ids, col)
        setSuspended(list, !list.allSatisfy { $0.queue == -1 }, model: model)
    }

    static func setSuspended(_ cards: [Card], _ suspend: Bool, model: AppModel) {
        model.edit { col in
            for var c in cards {
                if suspend {
                    c.queue = -1
                } else if c.queue == -1 {
                    c.queue = c.type == 0 ? 0 : (c.type == 2 ? 2 : (c.due > 1_000_000_000 ? 1 : 3))
                }
                c.mod = max(c.mod + 1, Int64(Date().timeIntervalSince1970))
                c.usn = -1
                try col.update(card: c)
            }
        }
    }

    static func setFlag(_ ids: Set<Int64>, _ flag: Int, model: AppModel) {
        guard let col = model.collectionHandle else { return }
        let list = cards(ids, col)
        model.edit { col in
            for var c in list {
                c.flags = (c.flags & ~7) | flag
                c.mod = max(c.mod + 1, Int64(Date().timeIntervalSince1970))
                c.usn = -1
                try col.update(card: c)
            }
        }
    }

    static func move(_ ids: Set<Int64>, toDeck deckID: Int64, model: AppModel) {
        model.edit { try $0.moveCards(Array(ids), toDeck: deckID) }
    }

    static func deleteNotes(of ids: Set<Int64>, model: AppModel) {
        guard let col = model.collectionHandle else { return }
        let notes = Array(Set(cards(ids, col).map(\.noteId)))
        model.edit { try $0.deleteNotes(notes) }
    }
}

/// Menu of card actions, used for context menus and the "操作" toolbar menu.
struct CardActionsMenu: View {
    @Environment(AppModel.self) private var model
    var ids: Set<Int64>
    var label = false
    var onDelete: (Set<Int64>) -> Void

    var body: some View {
        if label {
            Menu { items } label: { Text("操作") }
        } else {
            items
        }
    }

    @ViewBuilder
    private var items: some View {
        if let col = model.collectionHandle, !ids.isEmpty {
            let suspended = CardActions.cards(ids, col).allSatisfy { $0.queue == -1 }
            Button { CardActions.toggleSuspend(ids, model: model) } label: {
                Label(suspended ? "保留を解除" : "保留にする", systemImage: suspended ? "play.circle" : "pause.circle")
            }
            Menu {
                ForEach(0..<8, id: \.self) { f in
                    Button { CardActions.setFlag(ids, f, model: model) } label: {
                        Label(FlagInfo.name(f), systemImage: f == 0 ? "flag.slash" : "flag.fill")
                    }
                }
            } label: { Label("フラグ", systemImage: "flag") }
            Menu {
                ForEach(col.sortedDecks.filter { !$0.isFiltered }) { d in
                    Button(String(repeating: "　", count: d.depth) + d.baseName) { CardActions.move(ids, toDeck: d.id, model: model) }
                }
            } label: { Label("デッキを変更", systemImage: "folder") }
            Divider()
            Button(role: .destructive) { onDelete(ids) } label: { Label("ノートを削除", systemImage: "trash") }
        }
    }
}

/// Deck / state / tag / order menus that edit the query (it stays plain Anki syntax).
struct FilterChips: View {
    @Environment(AppModel.self) private var model
    @Binding var query: String
    @Binding var order: BrowseOrder

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("すべて") { set("deck:", nil) }
                    ForEach(model.collectionHandle?.sortedDecks.filter { !$0.isFiltered } ?? []) { d in
                        Button(String(repeating: "　", count: d.depth) + d.baseName) { set("deck:", "\"\(d.name)\"") }
                    }
                } label: { FilterChipLabel(title: "デッキ", value: current("deck:") ?? "すべて", active: current("deck:") != nil) }
                Menu {
                    Button("すべて") { set("is:", nil) }
                    Button("期日") { set("is:", "due") }
                    Button("新規") { set("is:", "new") }
                    Button("学習中") { set("is:", "learn") }
                    Button("復習") { set("is:", "review") }
                    Button("保留中") { set("is:", "suspended") }
                } label: { FilterChipLabel(title: "状態", value: stateTitle, active: current("is:") != nil) }
                Menu {
                    Button("すべて") { set("tag:", nil) }
                    ForEach(model.tags, id: \.self) { t in Button(t) { set("tag:", t.contains(" ") ? "\"\(t)\"" : t) } }
                } label: { FilterChipLabel(title: "タグ", value: current("tag:") ?? "すべて", active: current("tag:") != nil) }
                Menu {
                    Picker("並べ替え", selection: $order) {
                        ForEach(BrowseOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: { FilterChipLabel(title: "並び", value: order.title, active: false) }
            }
            .padding(.horizontal, 16)
        }
    }

    private var stateTitle: String {
        switch current("is:") {
        case "due": return "期日"
        case "new": return "新規"
        case "learn": return "学習中"
        case "review": return "復習"
        case "suspended": return "保留中"
        default: return "すべて"
        }
    }

    private func current(_ prefix: String) -> String? {
        CardSearchTokens.tokens(query).first { $0.lowercased().hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .map { $0.components(separatedBy: "::").last ?? $0 }
    }

    private func set(_ prefix: String, _ value: String?) {
        var tokens = CardSearchTokens.rawTokens(query).filter { !$0.lowercased().hasPrefix(prefix) }
        if let value { tokens.append(prefix + value) }
        query = tokens.joined(separator: " ")
    }
}

/// Splits a query into its terms, keeping quotes (for editing the query from chips).
enum CardSearchTokens {
    static func rawTokens(_ query: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for ch in query {
            if ch == "\"" { inQuotes.toggle() }
            if !inQuotes && (ch == " " || ch == "\u{3000}") {
                if !current.isEmpty { out.append(current) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func tokens(_ query: String) -> [String] { rawTokens(query) }
}

/// Editor of the selected card's note, saved automatically (pushed in compact widths, inspector in regular).
struct BrowseEditorPane: View {
    @Environment(AppModel.self) private var app
    let cardID: Int64
    let noteID: Int64
    @State private var model: NoteEditorModel?
    @State private var focus = FieldFocus()
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let model {
                let sections = NoteEditorSections(model: model, focus: focus, onFieldChange: scheduleSave)
                Form {
                    Section {
                        HStack {
                            if let error = model.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.learning)
                            } else if let status = model.status {
                                Label(status, systemImage: status == "編集中…" ? "pencil" : "checkmark.circle.fill")
                                    .foregroundStyle(status == "編集中…" ? Color.secondary : Theme.review)
                            } else {
                                Label("変更は自動で保存されます", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    }
                    sections
                    NotePreviewSection(model: model)
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("ノートを削除", systemImage: "trash") }
                    }
                }
                .background { FormatShortcuts(actions: sections.actions) }
                .scrollDismissesKeyboard(.interactively)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("ノートを編集")
        .navigationBarTitleDisplayMode(.inline)
        .background {
            Button("") { saveNow() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .confirmationDialog("このノートを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { model?.delete() }
        }
        .task {
            guard model == nil else { return }
            let m = NoteEditorModel(app: app)
            m.load(noteID: noteID)
            model = m
        }
        .onDisappear { saveNow() }
    }

    private func scheduleSave() {
        model?.status = "編集中…"
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        guard let model, model.hasChanges || model.status == "編集中…" else { return }
        model.save()
    }
}
