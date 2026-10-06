import Charts
import NegotoCore
import SwiftUI

/// Search query for a deck and its subdecks.
func deckQuery(_ name: String) -> String { "deck:\"\(name)\"" }

/// Decks: today's summary and the deck list, with the selected deck's detail next to it when there's room
/// (Medium and Wide), or pushed on a stack (Compact).
struct DecksScreen: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions
    var todayOnly = false
    @State private var path: [Int64] = []

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 600 {
                split(width: geo.size.width)
            } else {
                NavigationStack(path: $path) {
                    DeckListPane(actions: actions, todayOnly: todayOnly, isSplit: false)
                        .navigationDestination(for: Int64.self) { id in
                            DeckDetailView(deckID: id, actions: actions)
                        }
                }
            }
        }
    }

    private func split(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            NavigationStack {
                DeckListPane(actions: actions, todayOnly: todayOnly, isSplit: true)
            }
            .frame(width: min(380, max(300, width * 0.36)))
            Divider().ignoresSafeArea()
            NavigationStack {
                if let id = model.selectedDeckID, model.collectionHandle?.decks[id] != nil {
                    DeckDetailView(deckID: id, actions: actions)
                        .id(id)
                } else {
                    ContentUnavailableView {
                        Label("デッキを選択", systemImage: "rectangle.on.rectangle")
                    } description: {
                        Text("上位のデッキを選ぶと、その下のデッキもまとめて学習できます。")
                    }
                    .background(Theme.background)
                }
            }
        }
        .onAppear(perform: selectDefault)
        .onChange(of: model.revision) { _, _ in selectDefault() }
    }

    private func selectDefault() {
        guard model.selectedDeckID == nil else { return }
        let roots = model.deckTree
        model.selectedDeckID = (roots.first { $0.counts.total > 0 } ?? roots.first)?.deck.id
    }
}

// MARK: - List

struct DeckListPane: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions
    var todayOnly: Bool
    var isSplit: Bool
    @AppStorage("collapsedDecks") private var collapsedStorage = ""
    @AppStorage("deckSort") private var sortByDue = false
    @State private var renaming: Deck?
    @State private var newName = ""
    @State private var deleting: Deck?
    @State private var optionsDeck: Deck?

    private var collapsed: Set<Int64> { Set(collapsedStorage.split(separator: ",").compactMap { Int64($0) }) }

    private func toggle(_ id: Int64) {
        var c = collapsed
        if c.contains(id) { c.remove(id) } else { c.insert(id) }
        collapsedStorage = c.map(String.init).joined(separator: ",")
    }

    private var rows: [(node: DeckNode, depth: Int)] {
        var out: [(DeckNode, Int)] = []
        func sorted(_ nodes: [DeckNode]) -> [DeckNode] {
            sortByDue ? nodes.sorted { $0.counts.total > $1.counts.total } : nodes
        }
        func walk(_ nodes: [DeckNode], _ depth: Int) {
            for n in sorted(nodes) {
                if todayOnly {
                    if n.counts.total > 0 { out.append((n, depth)) }
                    if let kids = n.children, n.counts.total > 0, !collapsed.contains(n.deck.id) { walk(kids, depth + 1) }
                } else {
                    out.append((n, depth))
                    if let kids = n.children, !collapsed.contains(n.deck.id) { walk(kids, depth + 1) }
                }
            }
        }
        walk(model.deckTree, 0)
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.isEmpty {
                    WelcomeCard(importFile: actions.importFile)
                } else {
                    TodayCard(condensed: isSplit)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: todayOnly ? "学習待ちのデッキ" : "すべてのデッキ") {
                            Menu {
                                Picker("並べ替え", selection: $sortByDue) {
                                    Text("名前順").tag(false)
                                    Text("学習待ちの多い順").tag(true)
                                }
                            } label: {
                                Text("並べ替え").font(.footnote.weight(.semibold))
                            }
                        }
                        deckList
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(todayOnly ? "今日" : (isSplit ? "すべてのデッキ" : "デッキ"))
        .navigationBarTitleDisplayMode(isSplit ? .inline : .large)
        .paneNavigationBar()
        .toolbar {
            SidebarToggleItem()
            ToolbarItemGroup(placement: .topBarTrailing) {
                SyncToolbarButton()
                AddMenu(actions: actions, deckID: model.selectedDeckID)
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
                    if let sel = model.selectedDeckID, model.collectionHandle?.deckAndChildren(d.id).contains(sel) == true {
                        model.selectedDeckID = nil
                    }
                    model.deleteDeck(d.id)
                }
            }
        } message: {
            Text("下位のデッキとカード、学習履歴も削除されます。" + (model.sync.isConfigured ? "同期している他の端末からも削除されます。" : "") + "この操作は取り消せません。")
        }
    }

    private var deckList: some View {
        let items = rows
        return VStack(spacing: 0) {
            if items.isEmpty {
                Text(todayOnly ? "今日学習するデッキはありません" : "デッキがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            ForEach(Array(items.enumerated()), id: \.element.node.id) { index, row in
                rowView(row.node, depth: row.depth)
                if index < items.count - 1 {
                    Divider().padding(.leading, 36 + CGFloat(row.depth) * 16)
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous))
    }

    @ViewBuilder
    private func rowView(_ node: DeckNode, depth: Int) -> some View {
        let label = DeckRowLabel(node: node, depth: depth, isCollapsed: collapsed.contains(node.deck.id),
                                 showsChevron: !isSplit, isSelected: isSplit && model.selectedDeckID == node.deck.id) {
            toggle(node.deck.id)
        }
        Group {
            if isSplit {
                Button { model.selectedDeckID = node.deck.id } label: { label }
                    .buttonStyle(.plain)
            } else {
                NavigationLink(value: node.deck.id) { label }
                    .buttonStyle(.plain)
            }
        }
        .contextMenu { menu(for: node.deck) }
    }

    @ViewBuilder
    private func menu(for deck: Deck) -> some View {
        Button { model.startStudy(DeckRef(deckID: deck.id)) } label: { Label("学習する", systemImage: "play.fill") }
        Button { model.editorRequest = .add(deckID: deck.id) } label: { Label("カードを追加", systemImage: "plus.rectangle") }
        Button { model.openBrowse(query: deckQuery(deck.name)) } label: { Label("カードを見る", systemImage: "list.bullet") }
        Button { optionsDeck = deck } label: { Label("オプション", systemImage: "slider.horizontal.3") }
        Button { newName = deck.name; renaming = deck } label: { Label("名前を変更", systemImage: "pencil") }
        Divider()
        Button(role: .destructive) { deleting = deck } label: { Label("削除", systemImage: "trash") }
    }
}

struct DeckRowLabel: View {
    var node: DeckNode
    var depth: Int
    var isCollapsed: Bool
    var showsChevron: Bool
    var isSelected: Bool
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if node.children != nil {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCollapsed ? "展開" : "折りたたむ")
            } else {
                DeckDot(id: node.deck.id).frame(width: 16)
            }
            Text(node.deck.baseName)
                .font(depth == 0 ? .subheadline.weight(.medium) : .subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            CountBadges(counts: node.counts)
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 12 + CGFloat(depth) * 16)
        .padding(.trailing, 12)
        .frame(minHeight: 46)
        .background(isSelected ? Theme.accentSoft : Color.clear)
        .contentShape(Rectangle())
    }
}

/// "今日の学習 · 124 枚が待っています" with the start button.
struct TodayCard: View {
    @Environment(AppModel.self) private var model
    var condensed = false

    var body: some View {
        let counts = model.totalCounts
        let done = model.reviewedToday
        VStack(alignment: .leading, spacing: condensed ? 10 : 14) {
            if !condensed {
                HStack {
                    Text("今日の学習").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if counts.total > 0 {
                        Text("約\(model.estimatedMinutes)分").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(counts.total)")
                    .font(.system(size: condensed ? 30 : 40, weight: .bold).monospacedDigit())
                Text(counts.total > 0 ? (condensed ? "枚・約\(model.estimatedMinutes)分" : "枚が待っています") : "枚 — 今日の学習は完了")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !condensed {
                HStack(spacing: 22) {
                    MetricView(value: "\(counts.new)", caption: "新規", color: Theme.new, size: 18)
                    MetricView(value: "\(counts.learning)", caption: "学習中", color: Theme.learning, size: 18)
                    MetricView(value: "\(counts.review)", caption: "復習", color: Theme.review, size: 18)
                }
                ProgressView(value: Double(done), total: Double(max(1, done + counts.total)))
                    .tint(Theme.accent)
            }
            Button { model.startStudy(.all) } label: {
                Text(counts.total > 0 ? (condensed ? "今日の学習を始める" : "学習を始める") : "完了しました")
            }
            .buttonStyle(AccentButtonStyle(height: condensed ? 40 : 46))
            .disabled(counts.total == 0)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(condensed ? 16 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

struct WelcomeCard: View {
    var importFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(Theme.accent)
            Text("Negotoへようこそ").font(.title2.weight(.bold))
            Text("AnkiWebの共有デッキや、Ankiから書き出した .apkg / .colpkg を読み込んで始めましょう。カードを自分で追加することもできます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Ankiデッキを読み込む", action: importFile)
                .buttonStyle(AccentButtonStyle(height: 46))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

// MARK: - Detail

struct DeckDetailView: View {
    @Environment(AppModel.self) private var model
    let deckID: Int64
    var actions: ShellActions
    @State private var stats: DeckDetailStats?
    @State private var showOptions = false
    @State private var showCustomStudy = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var deleting = false
    @State private var width: CGFloat = 0

    private var deck: Deck? { model.collectionHandle?.decks[deckID] }

    var body: some View {
        let node = model.node(for: deckID)
        let counts = node?.counts ?? DeckCounts()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(node: node)
                HStack(spacing: 10) {
                    countTile(counts.new, "新規", Theme.new)
                    countTile(counts.learning, "学習中", Theme.learning)
                    countTile(counts.review, "復習", Theme.review)
                }
                actionButtons(counts: counts)
                if let children = node?.children, !children.isEmpty { subdecks(children) }
                if let stats {
                    if width >= 640 {
                        HStack(alignment: .top, spacing: 14) {
                            forecastCard(stats)
                            infoCard(stats)
                        }
                    } else {
                        forecastCard(stats)
                        infoCard(stats)
                    }
                }
                descriptionCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .padding(.bottom, 24)
            .readWidth(into: $width)
            .readableWidth(900)
        }
        .background(Theme.background)
        .navigationTitle(deck?.baseName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .paneNavigationBar()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.openBrowse(query: deckQuery(deck?.name ?? "")) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("このデッキのカードを検索")
                AddMenu(actions: actions, deckID: deckID)
                SyncToolbarButton()
                Menu {
                    Button { newName = deck?.name ?? ""; renaming = true } label: { Label("名前を変更", systemImage: "pencil") }
                    Button { showOptions = true } label: { Label("オプション", systemImage: "slider.horizontal.3") }
                    Divider()
                    Button(role: .destructive) { deleting = true } label: { Label("削除", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("その他")
            }
        }
        .sheet(isPresented: $showOptions) { DeckOptionsView(deckID: deckID) }
        .sheet(isPresented: $showCustomStudy) { CustomStudySheet(deckID: deckID) }
        .alert("デッキ名を変更", isPresented: $renaming) {
            TextField("名前（「::」で階層）", text: $newName)
            Button("キャンセル", role: .cancel) {}
            Button("変更") { model.renameDeck(deckID, to: newName) }
        }
        .confirmationDialog("「\(deck?.baseName ?? "")」を削除しますか？", isPresented: $deleting, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                model.selectedDeckID = nil
                model.deleteDeck(deckID)
            }
        } message: {
            Text("下位のデッキとカード、学習履歴も削除されます。この操作は取り消せません。")
        }
        .onAppear(perform: load)
        .onChange(of: model.revision) { _, _ in load() }
    }

    private func load() {
        guard let col = model.collectionHandle, col.decks[deckID] != nil else { return }
        stats = DeckDetailStats(col, deckID: deckID)
    }

    private func header(node: DeckNode?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let parent = deck?.parentName {
                Text(parent.replacingOccurrences(of: "::", with: " › "))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(deck?.baseName ?? "")
                .font(.title.weight(.bold))
                .lineLimit(3)
            if let stats {
                Text(subtitle(stats, children: node?.children?.count ?? 0))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func subtitle(_ s: DeckDetailStats, children: Int) -> String {
        var parts = ["\(Format.number(s.states.total))枚"]
        if children > 0 { parts.append("サブデッキ\(children)") }
        if let last = s.lastStudied { parts.append("最終学習 \(Format.relativeDay(last))") }
        return parts.joined(separator: "・")
    }

    private func countTile(_ n: Int, _ title: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.system(size: 28, weight: .bold).monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous))
    }

    @ViewBuilder
    private func actionButtons(counts: DeckCounts) -> some View {
        let start = Button { model.startStudy(DeckRef(deckID: deckID)) } label: {
            Text(counts.total > 0 ? "学習を始める" : "今日の学習は完了")
        }
        .buttonStyle(AccentButtonStyle(height: 42))
        .disabled(counts.total == 0)
        .keyboardShortcut(.defaultAction)
        let custom = Button("カスタム学習") { showCustomStudy = true }.buttonStyle(SoftButtonStyle(height: 42))
        let options = Button("オプション") { showOptions = true }.buttonStyle(SoftButtonStyle(height: 42))
        if width >= 520 {
            HStack(spacing: 10) {
                start.frame(maxWidth: .infinity)
                custom.frame(maxWidth: 160)
                options.frame(maxWidth: 140)
            }
        } else {
            VStack(spacing: 10) {
                start
                HStack(spacing: 10) { custom; options }
            }
        }
    }

    private func subdecks(_ children: [DeckNode]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("サブデッキ（まとめて学習します）")
            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.element.id) { i, child in
                    NavigationLink { DeckDetailView(deckID: child.deck.id, actions: actions) } label: {
                        HStack(spacing: 10) {
                            DeckDot(id: child.deck.id)
                            Text(child.deck.baseName).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            CountBadges(counts: child.counts)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < children.count - 1 { Divider().padding(.leading, 32) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous))
        }
    }

    private func forecastCard(_ s: DeckDetailStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今後7日間の予測").font(.subheadline.weight(.semibold))
            ForecastChart(days: s.forecast)
                .frame(height: 150)
        }
        .surface(padding: 16)
        .frame(maxWidth: .infinity)
    }

    private func infoCard(_ s: DeckDetailStats) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("デッキ情報").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
                MetricView(value: Format.percent(s.retention, digits: 1), caption: "平均保持率（30日）")
                MetricView(value: Format.number(s.states.mature), caption: "成熟カード")
                MetricView(value: Format.number(s.states.new), caption: "未学習")
                MetricView(value: Format.number(s.states.suspended), caption: "一時停止")
            }
            if let col = model.collectionHandle, let deck {
                let conf = col.deckConfig(for: deck.id)
                Text("プリセット「\(conf.name)」・新規 \(deck.newLimit ?? conf.newPerDay)/日・復習 \(deck.reviewLimit ?? conf.reviewsPerDay)/日・\(col.fsrsEnabled ? "FSRS" : "SM-2")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .surface(padding: 16)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var descriptionCard: some View {
        if let deck, !HTMLText.strip(deck.description).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("説明").font(.subheadline.weight(.semibold))
                Text(HTMLText.strip(deck.description.replacingOccurrences(of: "<br>", with: "\n")))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .surface(padding: 16)
        }
    }
}

/// Bars for the next days: today in the accent colour, later days in a soft tint, values on top.
struct ForecastChart: View {
    var days: [CollectionStatistics.ForecastDay]

    var body: some View {
        Chart(days) { d in
            BarMark(x: .value("日", label(d.day)), y: .value("枚数", d.total), width: .ratio(0.7))
                .foregroundStyle(d.day == 0 ? Theme.accent : Theme.accentSoft)
                .cornerRadius(5)
                .annotation(position: .top, spacing: 2) {
                    Text("\(d.total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.caption2) }
        }
    }

    private func label(_ day: Int) -> String {
        if day == 0 { return "今日" }
        let date = Calendar.current.date(byAdding: .day, value: day, to: Date()) ?? Date()
        return date.formatted(.dateTime.weekday(.narrow))
    }
}

struct DeckDetailStats {
    var states: CollectionStatistics.CardStates
    var forecast: [CollectionStatistics.ForecastDay]
    var retention: Double?
    var lastStudied: Date?

    init(_ col: AnkiCollection, deckID: Int64) {
        let s = CollectionStatistics(collection: col, deckID: deckID)
        states = s.cardStates()
        forecast = s.forecast(days: 7)
        retention = s.trueRetention(days: 30)
        lastStudied = s.lastStudied()
    }
}

// MARK: - Custom study

/// Anki's custom study, without filtered decks: raise today's limits, or practise a set of cards
/// without changing their schedule.
struct CustomStudySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deckID: Int64
    @State private var extraNew = 10
    @State private var extraReview = 50
    @State private var forgottenDays = 7
    @State private var lapses = 3

    private var name: String { model.collectionHandle?.decks[deckID]?.name ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $extraNew, in: 1...500, step: 5) { LabeledContent("新規カードを追加", value: "+\(extraNew)枚") }
                    Button("今日の新規カードを増やす") {
                        model.extendToday(deckID: deckID, new: extraNew, review: 0)
                        dismiss()
                    }
                    Stepper(value: $extraReview, in: 10...9999, step: 10) { LabeledContent("復習を追加", value: "+\(extraReview)枚") }
                    Button("今日の復習の上限を増やす") {
                        model.extendToday(deckID: deckID, new: 0, review: extraReview)
                        dismiss()
                    }
                } header: {
                    Text("今日の上限")
                } footer: {
                    Text("今日だけ、このデッキの1日の上限を増やします。")
                }
                Section {
                    practiceRow("苦手なカード", detail: "ラプス\(lapses)回以上", query: "\(deckQuery(name)) prop:lapses>=\(lapses)")
                    Stepper("ラプスの回数: \(lapses)回以上", value: $lapses, in: 1...20)
                    practiceRow("最近忘れたカード", detail: "過去\(forgottenDays)日に「もう一度」", query: "\(deckQuery(name)) rated:\(forgottenDays):1")
                    Stepper("期間: \(forgottenDays)日", value: $forgottenDays, in: 1...365)
                    practiceRow("先取り復習", detail: "今後7日に期日が来るカード", query: "\(deckQuery(name)) prop:due>0 prop:due<=7")
                    practiceRow("このデッキのすべてのカード", detail: "保留中を除く", query: "\(deckQuery(name)) -is:suspended")
                } header: {
                    Text("練習")
                } footer: {
                    Text("練習では、答えても次回の復習日は変わりません。")
                }
            }
            .navigationTitle("カスタム学習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func practiceRow(_ title: String, detail: String, query: String) -> some View {
        let count = model.collectionHandle?.countCards(query) ?? 0
        return Button {
            dismiss()
            model.practice(title: title, query: query)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(count)枚").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .disabled(count == 0)
    }
}
