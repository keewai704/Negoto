import Charts
import NegotoCore
import SwiftUI

/// Deck tree (sets and decks) with a detail pane. Two columns on iPad / wide windows, a stack on iPhone.
struct DecksView: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool
    @State private var selection: Int64?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DeckListColumn(selection: $selection, showImporter: $showImporter)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            NavigationStack {
                if let selection, model.collectionHandle?.decks[selection] != nil {
                    DeckDetailView(deckID: selection)
                        .id(selection)
                } else {
                    ContentUnavailableView {
                        Label("デッキを選択", systemImage: "square.stack")
                    } description: {
                        Text("上位のデッキ（セット）を選ぶと、その下のデッキをまとめて学習できます。")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct DeckListColumn: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Int64?
    @Binding var showImporter: Bool
    @AppStorage("collapsedDecks") private var collapsedStorage = ""
    @State private var renaming: Deck?
    @State private var newName = ""
    @State private var deleting: Deck?
    @State private var optionsDeck: Deck?
    @State private var search = ""

    private var collapsed: Set<Int64> { Set(collapsedStorage.split(separator: ",").compactMap { Int64($0) }) }

    private func toggle(_ id: Int64) {
        var c = collapsed
        if c.contains(id) { c.remove(id) } else { c.insert(id) }
        collapsedStorage = c.map(String.init).joined(separator: ",")
    }

    private var rows: [(node: DeckNode, depth: Int)] {
        var out: [(DeckNode, Int)] = []
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        func walk(_ nodes: [DeckNode], _ depth: Int) {
            for n in nodes {
                if query.isEmpty {
                    out.append((n, depth))
                    if let kids = n.children, !collapsed.contains(n.deck.id) { walk(kids, depth + 1) }
                } else {
                    if n.deck.name.lowercased().contains(query) { out.append((n, 0)) }
                    if let kids = n.children { walk(kids, 0) }
                }
            }
        }
        walk(model.deckTree, 0)
        return out
    }

    var body: some View {
        List(selection: $selection) {
            if model.isEmpty {
                Section {
                    Button { showImporter = true } label: {
                        Label("Ankiデッキを読み込む", systemImage: "tray.and.arrow.down.fill")
                    }
                } footer: {
                    Text("AnkiWebの共有デッキやAnkiから書き出した .apkg / .colpkg を読み込めます。")
                }
            } else {
                Section {
                    ForEach(rows, id: \.node.id) { row in
                        DeckRow(node: row.node, depth: row.depth, isCollapsed: collapsed.contains(row.node.deck.id),
                                showsDisclosure: search.isEmpty) { toggle(row.node.deck.id) }
                            .tag(row.node.deck.id)
                            .swipeActions(edge: .trailing) {
                                Button { model.startStudy(row.node.ref) } label: { Label("学習", systemImage: "play.fill") }
                                    .tint(.accentColor)
                            }
                            .contextMenu { menu(for: row.node.deck) }
                    }
                } header: {
                    HStack {
                        Text("デッキ")
                        Spacer()
                        Text("新規・学習中・復習").font(.caption2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .sidebar, prompt: "デッキを検索")
        .navigationTitle("デッキ")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SyncToolbarButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: { Label("デッキを読み込む", systemImage: "plus") }
            }
        }
        .refreshable {
            model.refreshCounts()
            model.sync.requestSync(force: true)
        }
        .sheet(item: $optionsDeck) { deck in DeckOptionsView(deckID: deck.id) }
        .alert("デッキ名を変更", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名前（「::」で階層）", text: $newName)
            Button("キャンセル", role: .cancel) {}
            Button("変更") { if let r = renaming { model.renameDeck(r.id, to: newName) } }
        }
        .confirmationDialog("「\(deleting?.baseName ?? "")」を削除しますか？",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let d = deleting {
                    if let sel = selection, model.collectionHandle?.deckAndChildren(d.id).contains(sel) == true { selection = nil }
                    model.deleteDeck(d.id)
                }
            }
        } message: {
            Text("下位のデッキとカード、学習履歴も削除されます。" + (model.sync.isConfigured ? "同期している他の端末からも削除されます。" : "") + "この操作は取り消せません。")
        }
    }

    @ViewBuilder
    private func menu(for deck: Deck) -> some View {
        Button { model.startStudy(DeckRef(deckID: deck.id)) } label: { Label("学習する", systemImage: "play.fill") }
        Button { optionsDeck = deck } label: { Label("学習オプション", systemImage: "slider.horizontal.3") }
        Button { newName = deck.name; renaming = deck } label: { Label("名前を変更", systemImage: "pencil") }
        Divider()
        Button(role: .destructive) { deleting = deck } label: { Label("削除", systemImage: "trash") }
    }
}

struct DeckRow: View {
    var node: DeckNode
    var depth: Int
    var isCollapsed: Bool
    var showsDisclosure = true
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if depth > 0 { Color.clear.frame(width: CGFloat(depth) * 18, height: 1) }
            if node.children != nil && showsDisclosure {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCollapsed ? "展開" : "折りたたむ")
            } else {
                Color.clear.frame(width: 22, height: 1)
            }
            Image(systemName: node.children != nil ? "square.stack.3d.up.fill" : "rectangle.portrait.fill")
                .font(.footnote)
                .foregroundStyle(node.children != nil ? Theme.nightBottom : Theme.nightTop.opacity(0.7))
                .frame(width: 22)
            Text(node.deck.baseName)
                .font(node.children != nil ? .body.weight(.semibold) : .body)
                .lineLimit(2)
            Spacer(minLength: 6)
            DuePills(counts: node.counts, size: .small)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Everything about one deck or set: today's counts, the study button, its decks and a few statistics.
struct DeckDetailView: View {
    @Environment(AppModel.self) private var model
    let deckID: Int64
    @State private var showOptions = false
    @State private var stats: DeckDetailStats?
    @State private var width: CGFloat = 0

    var body: some View {
        let node = model.node(for: deckID)
        let counts = node?.counts ?? DeckCounts()
        let layout = LayoutWidth(width)
        ScrollView {
            AdaptiveColumns(width: width, sideBySide: width >= 760, leadingFraction: 0.5) {
                header(node: node, counts: counts)
                if let children = node?.children, !children.isEmpty { childList(children) }
                actions
            } trailing: {
                if let stats { statsSection(stats, tileColumns: width >= 760 ? 2 : (layout == .compact ? 2 : 4)) }
            }
            .readWidth(into: $width)
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, 16)
            .readableWidth(1200)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.collectionHandle?.decks[deckID]?.baseName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showOptions) { DeckOptionsView(deckID: deckID) }
        .onAppear(perform: loadStats)
        .onChange(of: model.revision) { _, _ in loadStats() }
    }

    private func childList(_ children: [DeckNode]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "このセットのデッキ", subtitle: "「学習する」で、これらをまとめて学習します")
            Surface(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { i, child in
                        NavigationLink { DeckDetailView(deckID: child.deck.id) } label: {
                            HStack {
                                Text(child.deck.baseName).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                DuePills(counts: child.counts, size: .small)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < children.count - 1 { Divider().padding(.leading, 12) }
                    }
                }
            }
        }
    }

    private func loadStats() {
        guard let col = model.collectionHandle, col.decks[deckID] != nil else { return }
        stats = DeckDetailStats(col, deckID: deckID)
    }

    private func header(node: DeckNode?, counts: DeckCounts) -> some View {
        let deck = model.collectionHandle?.decks[deckID]
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                if let parent = deck?.parentName {
                    Text(parent.replacingOccurrences(of: "::", with: " › "))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(deck?.baseName ?? "")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
            HStack(spacing: 0) {
                heroCount("新規", counts.new, Theme.new)
                heroCount("学習中", counts.learning, Theme.learning)
                heroCount("復習", counts.review, Theme.review)
            }
            Button { model.startStudy(DeckRef(deckID: deckID)) } label: {
                Label(counts.total > 0 ? "学習する" : "今日の学習は完了", systemImage: counts.total > 0 ? "play.fill" : "checkmark")
                    .wideLabel()
            }
            .primaryActionStyle(onNight: true)
            .disabled(counts.total == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.night)
                StarField().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }

    private func heroCount(_ title: String, _ n: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)")
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsSection(_ s: DeckDetailStats, tileColumns: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "このデッキの状況")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: tileColumns), spacing: 12) {
                StatTile(icon: "rectangle.stack.fill", title: "カード", value: "\(s.states.total)", tint: Theme.new)
                StatTile(icon: "leaf.fill", title: "定着したカード", value: Format.percent(s.states.total == 0 ? nil : Double(s.states.mature) / Double(s.states.total)), tint: Theme.mature)
                StatTile(icon: "checkmark.seal.fill", title: "正答率（30日）", value: Format.percent(s.correctRate), tint: Theme.review)
                StatTile(icon: "calendar", title: "明日の予定", value: "\(s.tomorrow)枚", tint: Theme.nightBottom)
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("カードの状態").font(.headline)
                    CardStateBar(states: s.states)
                    Text("今後7日間の予定").font(.headline).padding(.top, 6)
                    Chart(s.forecast) { d in
                        BarMark(x: .value("日", d.day == 0 ? "今日" : "\(d.day)日後"), y: .value("枚数", d.total))
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(4)
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { showOptions = true } label: { Label("学習オプション", systemImage: "slider.horizontal.3").wideLabel(minHeight: 28) }
                .secondaryActionStyle()
            NavigationLink { BrowseView(ref: DeckRef(deckID: deckID)) } label: {
                Label("カードを一覧表示", systemImage: "list.bullet.rectangle").wideLabel(minHeight: 28)
            }
            .secondaryActionStyle()
            if let col = model.collectionHandle, let deck = col.decks[deckID] {
                let conf = col.deckConfig(for: deck.id)
                Text("プリセット「\(conf.name)」・新規 \(deck.newLimit ?? conf.newPerDay)枚/日・復習 \(deck.reviewLimit ?? conf.reviewsPerDay)枚/日・\(col.fsrsEnabled ? "FSRS" : "SM-2")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                if !HTMLText.strip(deck.description).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Surface {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("説明").font(.headline)
                            Text(HTMLText.strip(deck.description.replacingOccurrences(of: "<br>", with: "\n")))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

struct DeckDetailStats {
    var states: CollectionStatistics.CardStates
    var forecast: [CollectionStatistics.ForecastDay]
    var correctRate: Double?
    var tomorrow: Int

    init(_ col: AnkiCollection, deckID: Int64) {
        let s = CollectionStatistics(collection: col, deckID: deckID)
        states = s.cardStates()
        forecast = s.forecast(days: 7)
        let buttons = s.answerButtons(days: 30)
        let total = buttons.values.reduce(0) { $0 + $1.total }
        let again = buttons.values.reduce(0) { $0 + $1.counts[0] }
        correctRate = total == 0 ? nil : Double(total - again) / Double(total)
        tomorrow = forecast.count > 1 ? forecast[1].total : 0
    }
}

/// Horizontal stacked bar of card states with a legend.
struct CardStateBar: View {
    var states: CollectionStatistics.CardStates

    private var parts: [(String, Int, Color)] {
        [("新規", states.new, Theme.new), ("学習中", states.learning + states.relearning, Theme.learning),
         ("復習中", states.young, Theme.young), ("定着", states.mature, Theme.mature),
         ("保留", states.suspended, Theme.suspended), ("延期", states.buried, Theme.buried)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts.filter { $0.1 > 0 }, id: \.0) { part in
                        Rectangle()
                            .fill(part.2)
                            .frame(width: max(3, geo.size.width * CGFloat(part.1) / CGFloat(max(1, states.total))))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            FlowLegend(items: parts.filter { $0.1 > 0 }.map { ($0.0 + " \($0.1)", $0.2) })
        }
    }
}

struct FlowLegend: View {
    var items: [(String, Color)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 5) {
                    Circle().fill(item.1).frame(width: 8, height: 8)
                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
