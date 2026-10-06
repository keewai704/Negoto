import Charts
import NegotoCore
import SwiftUI

/// Search query for a deck and its subdecks.
func deckQuery(_ name: String) -> String { "deck:\"\(name)\"" }

/// Opens a deck: pushed on the decks stack in compact widths, selected in the sidebar in regular widths.
struct DeckLink<Label: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    let deckID: Int64
    @ViewBuilder var label: Label

    var body: some View {
        if hSize == .regular {
            Button { model.openDeck(deckID) } label: { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: deckID) { label }
        }
    }
}

// MARK: - Deck list ("デッキ" tab / "今日の学習")

struct DeckListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    var actions: ShellActions
    @AppStorage("collapsedDecks") private var collapsedStorage = ""
    @AppStorage("deckSort") private var sortByDue = false
    @State private var search = ""

    private var collapsed: Set<Int64> { Set(collapsedStorage.split(separator: ",").compactMap { Int64($0) }) }

    private func toggle(_ id: Int64) {
        var c = collapsed
        if c.contains(id) { c.remove(id) } else { c.insert(id) }
        withAnimation(.snappy) { collapsedStorage = c.map(String.init).joined(separator: ",") }
    }

    private var rows: [(node: DeckNode, depth: Int)] {
        var out: [(DeckNode, Int)] = []
        func sorted(_ nodes: [DeckNode]) -> [DeckNode] {
            sortByDue ? nodes.sorted { $0.counts.total > $1.counts.total } : nodes
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        func walk(_ nodes: [DeckNode], _ depth: Int) {
            for n in sorted(nodes) {
                if !query.isEmpty {
                    // Searching: a flat list of every matching deck.
                    if n.deck.name.localizedCaseInsensitiveContains(query) { out.append((n, 0)) }
                    if let kids = n.children { walk(kids, 0) }
                    continue
                }
                out.append((n, depth))
                if let kids = n.children, !collapsed.contains(n.deck.id) { walk(kids, depth + 1) }
            }
        }
        walk(model.deckTree, 0)
        return out
    }

    var body: some View {
        List {
            if model.isEmpty {
                Section { WelcomeView(importFile: actions.importFile) }
            } else {
                if search.isEmpty {
                    Section { TodaySummary() }
                }
                Section {
                    let items = rows
                    if items.isEmpty {
                        Text(search.isEmpty ? "デッキがありません" : "「\(search)」に一致するデッキはありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items, id: \.node.id) { item in
                        row(item.node, depth: item.depth)
                    }
                } header: {
                    HStack(alignment: .lastTextBaseline) {
                        Text("すべてのデッキ")
                        Spacer()
                        DeckCountsHeader().padding(.trailing, hSize == .regular ? 0 : 18)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableScrollMargins(860)
        .navigationTitle(hSize == .regular ? "今日の学習" : "デッキ")
        .searchable(text: $search, prompt: "デッキを検索")
        .refreshable {
            model.refreshCounts()
            model.sync.requestSync(force: true)
        }
        .toolbar {
            if hSize != .regular {
                ToolbarItem(placement: .topBarLeading) { SyncToolbarButton() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("並べ替え", selection: $sortByDue) {
                        Label("名前順", systemImage: "textformat").tag(false)
                        Label("学習待ちの多い順", systemImage: "number").tag(true)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("並べ替え")
                if hSize != .regular {
                    AddMenu(actions: actions, deckID: nil)
                }
            }
        }
    }

    private func row(_ node: DeckNode, depth: Int) -> some View {
        DeckLink(deckID: node.deck.id) {
            DeckRow(node: node, depth: depth, isCollapsed: collapsed.contains(node.deck.id),
                    showsDisclosure: search.isEmpty) { toggle(node.deck.id) }
        }
        .swipeActions(edge: .leading) {
            Button { model.startStudy(DeckRef(deckID: node.deck.id)) } label: { Label("学習", systemImage: "play.fill") }
                .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { model.deletingDeckID = node.deck.id } label: { Label("削除", systemImage: "trash") }
            Button { model.deckOptionsTarget = DeckRef(deckID: node.deck.id) } label: { Label("オプション", systemImage: "gearshape") }
                .tint(.gray)
        }
        .contextMenu { DeckMenuItems(deck: node.deck) }
    }
}

struct DeckRow: View {
    var node: DeckNode
    var depth: Int
    var isCollapsed: Bool
    var showsDisclosure = true
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if node.children != nil && showsDisclosure {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCollapsed ? "サブデッキを表示" : "サブデッキを隠す")
            } else {
                DeckDot(id: node.deck.id).frame(width: 22)
            }
            Text(showsDisclosure ? node.deck.baseName : node.deck.name.replacingOccurrences(of: "::", with: " › "))
                .font(depth == 0 ? .body.weight(.medium) : .body)
                .lineLimit(2)
            Spacer(minLength: 8)
            DeckCountsView(counts: node.counts)
        }
        .padding(.leading, CGFloat(depth) * 20)
        .frame(minHeight: 36)
    }
}

/// Today's work over every deck, with the start button.
struct TodaySummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let counts = model.totalCounts
        let done = model.reviewedToday
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今日の学習").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if counts.total > 0 {
                    Text("約\(model.estimatedMinutes)分").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if counts.total > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(counts.total)").font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                    Text("枚").font(.headline).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    MetricView(value: "\(counts.new)", caption: "新規", color: Theme.new, font: .title2.weight(.bold))
                    MetricView(value: "\(counts.learning)", caption: "学習中", color: Theme.learning, font: .title2.weight(.bold))
                    MetricView(value: "\(counts.review)", caption: "復習", color: Theme.review, font: .title2.weight(.bold))
                }
            } else {
                Label("今日の学習は完了しました", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.review)
            }
            if done > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(done), total: Double(max(1, done + counts.total)))
                    Text("今日は \(done) 枚学習しました").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if counts.total > 0 {
                Button { model.startStudy(.all) } label: {
                    Label("学習を始める", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .primaryActionStyle()
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.vertical, 6)
    }
}

struct WelcomeView: View {
    var importFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("Negotoへようこそ").font(.title2.weight(.bold))
            Text("AnkiWebの共有デッキや、Ankiから書き出した .apkg / .colpkg を読み込んで始めましょう。カードを自分で追加することもできます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: importFile) {
                Label("Ankiデッキを読み込む", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Deck overview

struct DeckOverviewView: View {
    @Environment(AppModel.self) private var model
    let deckID: Int64
    var actions: ShellActions
    @State private var stats: DeckDetailStats?
    @State private var width: CGFloat = 0

    private var deck: Deck? { model.collectionHandle?.decks[deckID] }

    var body: some View {
        let node = model.node(for: deckID)
        let counts = node?.counts ?? DeckCounts()
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(node: node)
                if width >= 700 {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) {
                            studyBlock(counts)
                            if let children = node?.children, !children.isEmpty { subdecks(children) }
                            if let stats { infoBlock(stats) }
                        }
                        VStack(spacing: 20) {
                            if let stats { forecastBlock(stats) }
                            descriptionBlock
                            presetBlock
                        }
                    }
                } else {
                    studyBlock(counts)
                    if let children = node?.children, !children.isEmpty { subdecks(children) }
                    if let stats { forecastBlock(stats) }
                    if let stats { infoBlock(stats) }
                    presetBlock
                    descriptionBlock
                }
            }
            .padding(.horizontal, width >= 700 ? 24 : 16)
            .padding(.bottom, 24)
            .readWidth(into: $width)
            .readableWidth(1040)
        }
        .background(Theme.background)
        .navigationTitle(deck?.baseName ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.openBrowse(query: deckQuery(deck?.name ?? "")) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("このデッキのカードを見る")
                Button { model.editorRequest = .add(deckID: deckID) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("カードを追加")
                if let deck {
                    Menu { DeckMenuItems(deck: deck) } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("その他")
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.revision) { _, _ in load() }
    }

    private func load() {
        guard let col = model.collectionHandle, col.decks[deckID] != nil else { return }
        stats = DeckDetailStats(col, deckID: deckID)
    }

    private func header(node: DeckNode?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let parent = deck?.parentName {
                Text(parent.replacingOccurrences(of: "::", with: " › "))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let stats {
                Text(subtitle(stats, children: node?.children?.count ?? 0))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func subtitle(_ s: DeckDetailStats, children: Int) -> String {
        var parts = ["\(Format.number(s.states.total))枚"]
        if children > 0 { parts.append("サブデッキ\(children)") }
        if let last = s.lastStudied { parts.append("最終学習 \(Format.relativeDay(last))") }
        return parts.joined(separator: "・")
    }

    private func studyBlock(_ counts: DeckCounts) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                MetricView(value: "\(counts.new)", caption: "新規", color: Theme.new, font: .largeTitle.weight(.bold))
                Spacer()
                MetricView(value: "\(counts.learning)", caption: "学習中", color: Theme.learning, font: .largeTitle.weight(.bold))
                Spacer()
                MetricView(value: "\(counts.review)", caption: "復習", color: Theme.review, font: .largeTitle.weight(.bold))
                Spacer()
            }
            Button { model.startStudy(DeckRef(deckID: deckID)) } label: {
                Label(counts.total > 0 ? "学習を始める" : "今日の学習は完了", systemImage: counts.total > 0 ? "play.fill" : "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .disabled(counts.total == 0)
            .keyboardShortcut(.defaultAction)
            HStack(spacing: 10) {
                Button { model.customStudyTarget = DeckRef(deckID: deckID) } label: { Text("カスタム学習").frame(maxWidth: .infinity) }
                Button { model.deckOptionsTarget = DeckRef(deckID: deckID) } label: { Text("オプション").frame(maxWidth: .infinity) }
            }
            .secondaryActionStyle()
            .font(.subheadline.weight(.semibold))
        }
        .surface(padding: 20)
    }

    private func subdecks(_ children: [DeckNode]) -> some View {
        Block(title: "サブデッキ（まとめて学習します）") {
            ForEach(Array(children.enumerated()), id: \.element.id) { i, child in
                DeckLink(deckID: child.deck.id) {
                    HStack(spacing: 10) {
                        DeckDot(id: child.deck.id).frame(width: 22)
                        Text(child.deck.baseName).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        DeckCountsView(counts: child.counts)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                }
                .buttonStyle(.plain)
                if i < children.count - 1 { Divider().padding(.leading, 48) }
            }
        }
    }

    private func forecastBlock(_ s: DeckDetailStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今後7日間").font(.headline)
            ForecastChart(days: s.forecast)
                .frame(height: 140)
        }
        .surface(padding: 18)
    }

    private func infoBlock(_ s: DeckDetailStats) -> some View {
        Block(title: "情報") {
            InfoRow("平均保持率（30日）", Format.percent(s.retention, digits: 1))
            InfoRow("成熟カード", Format.number(s.states.mature))
            InfoRow("未学習", Format.number(s.states.new))
            InfoRow("保留中", Format.number(s.states.suspended), last: true)
        }
    }

    @ViewBuilder
    private var presetBlock: some View {
        if let col = model.collectionHandle, let deck {
            let conf = col.deckConfig(for: deck.id)
            Block(title: "設定") {
                Button { model.deckOptionsTarget = DeckRef(deckID: deckID) } label: {
                    InfoRow("プリセット", conf.name, chevron: true)
                }
                .buttonStyle(.plain)
                InfoRow("1日の上限", "新規 \(deck.newLimit ?? conf.newPerDay)・復習 \(deck.reviewLimit ?? conf.reviewsPerDay)")
                InfoRow("スケジューラ", col.fsrsEnabled ? "FSRS" : "SM-2", last: true)
            }
        }
    }

    @ViewBuilder
    private var descriptionBlock: some View {
        if let deck, !HTMLText.strip(deck.description).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("説明").font(.headline)
                Text(HTMLText.strip(deck.description.replacingOccurrences(of: "<br>", with: "\n")))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .surface(padding: 18)
        }
    }
}

/// A titled, opaque block of rows (like a section of an inset-grouped list) for scroll views.
struct Block<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.blockRadius, style: .continuous))
        }
    }
}

/// A "title … value" row inside a Block.
struct InfoRow: View {
    var title: String
    var value: String
    var last = false
    var chevron = false

    init(_ title: String, _ value: String, last: Bool = false, chevron: Bool = false) {
        self.title = title
        self.value = value
        self.last = last
        self.chevron = chevron
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 12)
                Text(value).foregroundStyle(.secondary).monospacedDigit().multilineTextAlignment(.trailing)
                if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            if !last { Divider().padding(.leading, 16) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bars for the next days: today in the accent colour, later days lighter, values on top.
struct ForecastChart: View {
    var days: [CollectionStatistics.ForecastDay]

    var body: some View {
        Chart(days) { d in
            BarMark(x: .value("日", label(d.day)), y: .value("枚数", d.total), width: .ratio(0.62))
                .foregroundStyle(d.day == 0 ? Theme.accent : Theme.accent.opacity(0.35))
                .cornerRadius(5)
                .annotation(position: .top, spacing: 3) {
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
                    Stepper(value: $extraNew, in: 1...500, step: 5) { LabeledContent("新規カード", value: "+\(extraNew)枚") }
                    Button("今日の新規カードを増やす") {
                        model.extendToday(deckID: deckID, new: extraNew, review: 0)
                        dismiss()
                    }
                    Stepper(value: $extraReview, in: 10...9999, step: 10) { LabeledContent("復習", value: "+\(extraReview)枚") }
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
                    practiceRow("苦手なカード", detail: "ラプス\(lapses)回以上", icon: "exclamationmark.triangle", query: "\(deckQuery(name)) prop:lapses>=\(lapses)")
                    Stepper("ラプスの回数: \(lapses)回以上", value: $lapses, in: 1...20)
                    practiceRow("最近忘れたカード", detail: "過去\(forgottenDays)日に「もう一度」", icon: "arrow.counterclockwise", query: "\(deckQuery(name)) rated:\(forgottenDays):1")
                    Stepper("期間: \(forgottenDays)日", value: $forgottenDays, in: 1...365)
                    practiceRow("先取り復習", detail: "今後7日に期日が来るカード", icon: "forward", query: "\(deckQuery(name)) prop:due>0 prop:due<=7")
                    practiceRow("このデッキのすべてのカード", detail: "保留中を除く", icon: "rectangle.stack", query: "\(deckQuery(name)) -is:suspended")
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

    private func practiceRow(_ title: String, detail: String, icon: String, query: String) -> some View {
        let count = model.collectionHandle?.countCards(query) ?? 0
        return Button {
            dismiss()
            model.practice(title: title, query: query)
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.primary)
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                }
                Spacer()
                Text("\(count)枚").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .disabled(count == 0)
    }
}
