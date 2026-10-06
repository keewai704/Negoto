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

/// Browse: Anki-style search with filter chips, the card table, and the note editor next to it
/// when there is room (or pushed on narrow windows).
struct BrowseScreen: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [BrowseRow] = []
    @State private var total = 0
    @State private var selection: Int64?
    @AppStorage("browseOrder") private var order: BrowseOrder = .created

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 760 {
                HStack(spacing: 0) {
                    NavigationStack { listPane(split: true) }
                        .frame(maxWidth: .infinity)
                    Divider().ignoresSafeArea()
                    NavigationStack {
                        if let selection, let row = rows.first(where: { $0.id == selection }) {
                            BrowseEditorPane(cardID: row.id, noteID: row.noteID)
                                .id(row.noteID)
                        } else {
                            ContentUnavailableView("カードを選択", systemImage: "rectangle.and.pencil.and.ellipsis",
                                                   description: Text("選んだカードをここで編集できます。"))
                                .background(Theme.background)
                        }
                    }
                    .frame(width: min(460, max(340, geo.size.width * 0.4)))
                }
            } else {
                NavigationStack {
                    listPane(split: false)
                        .navigationDestination(for: BrowseRow.self) { row in
                            BrowseEditorPane(cardID: row.id, noteID: row.noteID)
                        }
                }
            }
        }
        .task(id: LoadKey(query: model.browseQuery, order: order, revision: model.revision)) {
            if !model.browseQuery.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            load()
        }
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
        if let s = selection, !rows.contains(where: { $0.id == s }) { selection = nil }
    }

    @ViewBuilder
    private func listPane(split: Bool) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            FilterChips(query: $model.browseQuery, order: $order)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            if split {
                Table(rows, selection: $selection) {
                    TableColumn("表面") { row in
                        HStack(spacing: 6) {
                            if row.flag > 0 { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(FlagInfo.color(row.flag)) }
                            Text(row.front.isEmpty ? "（空）" : row.front).lineLimit(1)
                        }
                        .opacity(row.queue < 0 ? 0.5 : 1)
                    }
                    TableColumn("デッキ") { row in Text(row.deck).foregroundStyle(.secondary).lineLimit(1) }
                        .width(min: 80, ideal: 120)
                    TableColumn("期日") { row in Text(row.due).foregroundStyle(.secondary).monospacedDigit() }
                        .width(min: 60, ideal: 70)
                    TableColumn("間隔") { row in Text(row.interval).foregroundStyle(.secondary).monospacedDigit() }
                        .width(min: 50, ideal: 60)
                }
                .contextMenu(forSelectionType: Int64.self) { ids in
                    rowMenu(ids)
                }
            } else {
                List(rows) { row in
                    NavigationLink(value: row) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.front.isEmpty ? "（空）" : row.front).lineLimit(2)
                                if row.flag > 0 { Image(systemName: "flag.fill").font(.caption).foregroundStyle(FlagInfo.color(row.flag)) }
                            }
                            Text("\(row.deck) · \(row.due) · \(row.interval)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .opacity(row.queue < 0 ? 0.5 : 1)
                    }
                    .contextMenu { rowMenu([row.id]) }
                }
                .listStyle(.plain)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView(model.browseQuery.isEmpty ? "カードがありません" : "見つかりません",
                                       systemImage: "magnifyingglass",
                                       description: Text("例: deck:\"英単語\" is:due tag:頻出 -is:suspended"))
            }
        }
        .background(Theme.background)
        .searchable(text: $model.browseQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "検索（Ankiの検索式が使えます）")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("ブラウズ")
        .navigationBarTitleDisplayMode(split ? .inline : .large)
        .toolbar {
            SidebarToggleItem()
            ToolbarItem(placement: .status) {
                Text(total > rows.count ? "\(Format.number(total))枚中\(Format.number(rows.count))枚" : "\(Format.number(total))枚")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { self.model.editorRequest = .add(deckID: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("カードを追加")
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<Int64>) -> some View {
        if !ids.isEmpty, let col = model.collectionHandle {
            let cards = ids.compactMap { try? col.card(id: $0) }
            let allSuspended = cards.allSatisfy { $0.queue == -1 }
            Button {
                setSuspended(cards, !allSuspended)
            } label: {
                Label(allSuspended ? "保留を解除" : "保留にする", systemImage: allSuspended ? "play.circle" : "pause.circle")
            }
            Menu {
                ForEach(0..<8, id: \.self) { f in
                    Button(FlagInfo.name(f)) { setFlag(cards, f) }
                }
            } label: { Label("フラグ", systemImage: "flag") }
            Divider()
            Button(role: .destructive) {
                let notes = Array(Set(cards.map(\.noteId)))
                model.edit { try $0.deleteNotes(notes) }
            } label: { Label("ノートを削除", systemImage: "trash") }
        }
    }

    private func setSuspended(_ cards: [Card], _ suspend: Bool) {
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

    private func setFlag(_ cards: [Card], _ flag: Int) {
        model.edit { col in
            for var c in cards {
                c.flags = (c.flags & ~7) | flag
                c.mod = max(c.mod + 1, Int64(Date().timeIntervalSince1970))
                c.usn = -1
                try col.update(card: c)
            }
        }
    }
}

/// Deck / state / tag / order chips that edit the query (it stays plain Anki syntax).
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
                } label: { chip("デッキ", current("deck:") ?? "すべて") }
                Menu {
                    Button("すべて") { set("is:", nil) }
                    Button("期日") { set("is:", "due") }
                    Button("新規") { set("is:", "new") }
                    Button("学習中") { set("is:", "learn") }
                    Button("復習") { set("is:", "review") }
                    Button("保留中") { set("is:", "suspended") }
                } label: { chip("状態", stateTitle) }
                Menu {
                    Button("すべて") { set("tag:", nil) }
                    ForEach(model.tags, id: \.self) { t in Button(t) { set("tag:", t.contains(" ") ? "\"\(t)\"" : t) } }
                } label: { chip("タグ", current("tag:") ?? "すべて") }
                Menu {
                    Picker("並べ替え", selection: $order) {
                        ForEach(BrowseOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: { chip("並び", order.title) }
            }
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

    private func chip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.15)))
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

/// Editor of the selected card's note, saved automatically.
struct BrowseEditorPane: View {
    @Environment(AppModel.self) private var app
    let cardID: Int64
    let noteID: Int64
    @State private var model: NoteEditorModel?
    @State private var focus = FieldFocus()
    @State private var saveTask: Task<Void, Never>?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            if let model {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("カードを編集").font(.title2.weight(.bold))
                        Spacer()
                        if let status = model.status {
                            Label(status, systemImage: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                    NoteEditorForm(model: model, focus: focus, onFieldChange: scheduleSave)
                    NotePreview(model: model)
                    Text("⌘S 保存 ・ ⇧⌘C 穴埋め")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { saveNow() } label: { Image(systemName: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityLabel("保存")
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("ノートを削除")
            }
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

/// Search tab: decks and cards matching the query.
struct SearchScreen: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var rows: [BrowseRow] = []
    @State private var total = 0

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Text("デッキ名やカードの内容で検索できます。Ankiの検索式（deck: tag: is:due など）も使えます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let decks = matchingDecks
                    if !decks.isEmpty {
                        Section("デッキ") {
                            ForEach(decks) { d in
                                Button {
                                    model.openDeck(d.id)
                                    model.section = .decks
                                } label: {
                                    HStack(spacing: 10) {
                                        DeckDot(id: d.id)
                                        Text(d.name.replacingOccurrences(of: "::", with: " › ")).foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(rows) { row in
                            NavigationLink(value: row) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.front.isEmpty ? "（空）" : row.front).lineLimit(2)
                                    Text("\(row.deck) · \(row.due)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if total > 0 {
                            Button("ブラウズで\(Format.number(total))枚すべてを開く") { model.openBrowse(query: query) }
                        }
                    } header: {
                        Text("カード")
                    }
                }
            }
            .navigationTitle("検索")
            .navigationDestination(for: BrowseRow.self) { row in
                BrowseEditorPane(cardID: row.id, noteID: row.noteID)
            }
            .searchable(text: $query, prompt: "デッキ・カードを検索")
            .textInputAutocapitalization(.never)
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(200))
                guard let col = model.collectionHandle, !query.isEmpty else { rows = []; total = 0; return }
                let result = BrowseLoader.load(col, query: query, order: .created, limit: 50)
                rows = result.rows
                total = result.total
            }
        }
    }

    private var matchingDecks: [Deck] {
        let q = query.lowercased()
        return (model.collectionHandle?.sortedDecks ?? []).filter { !$0.isFiltered && $0.name.lowercased().contains(q) }.prefix(8).map { $0 }
    }
}

/// Read-only card preview (kept for deep links from older screens).
struct CardPreviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    let cardID: Int64
    @State private var showAnswer = false

    var body: some View {
        Group {
            if let col = app.collectionHandle, let card = try? col.card(id: cardID),
               let note = try? col.note(id: card.noteId), let nt = col.notetypes[note.notetypeId] {
                let resolver = MediaResolver(folder: col.mediaFolder)
                let rendered = CardRenderer.render(card: card, note: note, notetype: nt, deckName: col.deckName(card.deckId),
                                                   mediaExists: { resolver.exists($0) })
                let html = CardPage.document(card: rendered, side: showAnswer ? .answer : .question, typedAnswer: nil,
                                             resolver: resolver,
                                             options: .init(nightMode: colorScheme == .dark, forceDarkCards: true,
                                                            isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                                            supportBaseURL: app.supportDirectory.absoluteString))
                CardWebView(html: html, mediaFolder: col.mediaFolder, readAccessRoot: app.libraryRoot)
            } else {
                ContentUnavailableView("カードが見つかりません", systemImage: "questionmark.square.dashed")
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("面", selection: $showAnswer) {
                    Text("表").tag(false)
                    Text("裏").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
    }
}
