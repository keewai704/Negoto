import Charts
import NegotoCore
import SwiftUI

/// Statistics as a grid of cards (minimum card width 320pt: one column on iPhone, up to three on iPad).
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var deckID: Int64 = AnkiCollection.allDecksID
    @State private var period: Period = .quarter
    @State private var data: StatsData?
    @State private var width: CGFloat = 0
    @State private var showInfo = false

    enum Period: Int, CaseIterable, Identifiable {
        case month = 30, quarter = 90, year = 365, all = 0
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .month: return "1か月"
            case .quarter: return "3か月"
            case .year: return "1年"
            case .all: return "全期間"
            }
        }
        var days: Int? { self == .all ? nil : rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("期間", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                if let data {
                    if data.totalReviews == 0 && data.states.total == 0 {
                        ContentUnavailableView("まだデータがありません", systemImage: "chart.bar",
                                               description: Text("デッキを読み込んで学習すると、ここに統計が表示されます。"))
                    } else {
                        grid(data)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .readWidth(into: $width)
            .padding(.horizontal, width >= 700 ? 24 : 16)
            .padding(.vertical, 8)
            .padding(.bottom, 24)
            .readableWidth(1200)
        }
        .background(Theme.background)
        .navigationTitle("統計")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { deckMenu }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let data {
                    ShareLink(item: data.summary(deck: deckTitle, period: period.title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("共有")
                }
                Button { showInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("統計について")
            }
        }
        .sheet(isPresented: $showInfo) { StatsInfoSheet() }
        .task(id: Key(deckID: deckID, period: period, revision: model.revision)) { load() }
    }

    struct Key: Equatable {
        var deckID: Int64
        var period: Period
        var revision: Int
    }

    private var deckTitle: String {
        deckID == AnkiCollection.allDecksID ? "すべてのデッキ" : (model.collectionHandle?.decks[deckID]?.baseName ?? "")
    }

    private func load() {
        guard let col = model.collectionHandle else { return }
        if deckID != AnkiCollection.allDecksID && col.decks[deckID] == nil { deckID = AnkiCollection.allDecksID }
        data = StatsData(col, deckID: deckID, period: period)
    }

    private var deckMenu: some View {
        Menu {
            Picker("デッキ", selection: $deckID) {
                Text("すべてのデッキ").tag(AnkiCollection.allDecksID)
                ForEach(model.collectionHandle?.sortedDecks.filter { !$0.isFiltered } ?? []) { d in
                    Text(String(repeating: "　", count: d.depth) + d.baseName).tag(d.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(deckTitle).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel("デッキ: \(deckTitle)")
    }

    // MARK: Grid

    private enum Item: Hashable {
        case today, retention, buttons, calendar, forecast, intervals, states
        var span: Int { self == .calendar || self == .intervals ? 2 : 1 }
    }

    private func grid(_ d: StatsData) -> some View {
        let spacing: CGFloat = 14
        let columns = max(1, min(3, Int((width + spacing) / (320 + spacing))))
        let order: [Item] = columns == 2
            ? [.today, .retention, .buttons, .forecast, .calendar, .intervals, .states]
            : [.today, .retention, .buttons, .calendar, .forecast, .intervals, .states]
        var rows: [[Item]] = []
        var row: [Item] = []
        var used = 0
        for item in order {
            let span = min(item.span, columns)
            if used + span > columns { rows.append(row); row = []; used = 0 }
            row.append(item)
            used += span
        }
        if !row.isEmpty { rows.append(row) }
        let unit = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, items in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(items, id: \.self) { item in
                        let span = min(item.span, columns)
                        card(item, d, width: unit * CGFloat(span) + spacing * CGFloat(span - 1) - 4)
                            .frame(maxWidth: items.count == 1 ? .infinity : unit * CGFloat(span) + spacing * CGFloat(span - 1))
                    }
                    if items.count == 1 && columns > 1 && min(items[0].span, columns) < columns { Spacer(minLength: 0) }
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ item: Item, _ d: StatsData, width: CGFloat) -> some View {
        switch item {
        case .today:
            StatCard(title: "今日") {
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    MetricView(value: "\(d.today.reviews)", unit: "枚", caption: "学習")
                    MetricView(value: "\(d.today.seconds / 60)", unit: "分", caption: "時間")
                    MetricView(value: d.today.correctRate.map { "\(Int(($0 * 100).rounded()))" } ?? "–", unit: "%", caption: "正答率")
                }
            }
        case .retention:
            StatCard(title: "保持率") {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.percent(d.retention, digits: 1)).font(.title.weight(.bold).monospacedDigit())
                        Text("目標 \(Int((d.desiredRetention * 100).rounded()))%").font(.caption2).foregroundStyle(.secondary)
                    }
                    Chart(d.retentionTrend) { p in
                        BarMark(x: .value("期間", String(p.startDay)), y: .value("保持率", p.rate ?? 0), width: .ratio(0.7))
                            .foregroundStyle((p.rate ?? 0) >= d.desiredRetention ? Theme.accent : Theme.accent.opacity(0.35))
                            .cornerRadius(2)
                    }
                    .chartYScale(domain: 0.5...1)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 50)
                }
            }
        case .buttons:
            StatCard(title: "回答ボタンの使用割合") {
                AnswerShareBar(counts: d.buttonTotals)
            }
        case .calendar:
            StatCard(title: "学習カレンダー", subtitle: d.streak.current > 0 ? "連続 \(d.streak.current)日" : nil) {
                ActivityHeatmap(counts: d.heatmap, width: width - 36)
            }
        case .forecast:
            StatCard(title: "今後7日間") {
                ForecastChart(days: d.forecast).frame(height: 120)
            }
        case .intervals:
            StatCard(title: "復習間隔の分布") {
                Chart(d.intervals) { b in
                    BarMark(x: .value("間隔", b.label), y: .value("枚数", b.count), width: .ratio(0.75))
                        .foregroundStyle(Theme.new)
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel().font(.caption2)
                    }
                }
                .frame(height: 150)
                HStack {
                    Text(d.intervals.first?.label ?? "").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(d.intervals.last?.label ?? "").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .states:
            StatCard(title: "カードの状態") {
                VStack(spacing: 9) {
                    stateRow("成熟（21日以上）", d.states.mature, Theme.accent)
                    stateRow("若い", d.states.young, Theme.young)
                    stateRow("学習中", d.states.learning + d.states.relearning, Theme.learning)
                    stateRow("未学習", d.states.new, Theme.new)
                    stateRow("一時停止", d.states.suspended, Theme.suspended)
                    if d.states.buried > 0 { stateRow("延期", d.states.buried, Theme.buried) }
                }
            }
        }
    }

    private func stateRow(_ title: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.subheadline)
            Spacer()
            Text(Format.number(n)).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

struct StatCard<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.blockRadius, style: .continuous))
    }
}

/// One bar split by answer button, with a legend.
struct AnswerShareBar: View {
    var counts: [Int]

    var body: some View {
        let total = max(1, counts.reduce(0, +))
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Rating.allCases, id: \.self) { r in
                        let n = counts[r.rawValue - 1]
                        if n > 0 {
                            Rectangle().fill(Theme.color(for: r))
                                .frame(width: max(3, (geo.size.width - 6) * CGFloat(n) / CGFloat(total)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack(spacing: 10) {
                ForEach(Rating.allCases, id: \.self) { r in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.color(for: r)).frame(width: 7, height: 7)
                        Text("\(Theme.title(for: r)) \(Int((Double(counts[r.rawValue - 1]) / Double(total) * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// GitHub-style calendar of reviews per day, as many weeks as fit (up to a year).
struct ActivityHeatmap: View {
    var counts: [Int: Int]
    var width: CGFloat

    var body: some View {
        let gap: CGFloat = 3
        let cell: CGFloat = max(9, min(15, (width - 52 * gap) / 53))
        let weeks = max(8, min(53, Int((width + gap) / (cell + gap))))
        let maxCount = max(1, counts.values.max() ?? 1)
        let todayWeekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7  // Monday = 0
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        let offset = -((weeks - 1 - w) * 7 + (todayWeekday - d))
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(color(offset > 0 ? nil : counts[offset], max: maxCount, future: offset > 0))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("学習カレンダー：\(counts.filter { $0.value > 0 }.count)日学習")
    }

    private func color(_ n: Int?, max: Int, future: Bool) -> Color {
        if future { return .clear }
        guard let n, n > 0 else { return Color.secondary.opacity(0.12) }
        let level = Double(n) / Double(max)
        return Theme.accent.opacity(level > 0.75 ? 1 : level > 0.5 ? 0.75 : level > 0.25 ? 0.5 : 0.3)
    }
}

struct StatsData {
    var today: CollectionStatistics.Today
    var streak: CollectionStatistics.Streak
    var heatmap: [Int: Int]
    var forecast: [CollectionStatistics.ForecastDay]
    var states: CollectionStatistics.CardStates
    var intervals: [CollectionStatistics.Bucket]
    var retention: Double?
    var retentionTrend: [CollectionStatistics.RetentionPoint]
    var desiredRetention: Double
    var buttonTotals: [Int]
    var totalReviews: Int

    init(_ col: AnkiCollection, deckID: Int64, period: StatsView.Period) {
        let s = CollectionStatistics(collection: col, deckID: deckID)
        today = s.todayStats()
        streak = s.streak()
        heatmap = s.heatmap(days: 371)
        forecast = s.forecast(days: 7)
        states = s.cardStates()
        intervals = s.intervalDistribution()
        retention = s.trueRetention(days: period.days)
        retentionTrend = s.retentionTrend(days: period.days ?? 365, buckets: 12)
        desiredRetention = col.deckConfig(for: deckID == AnkiCollection.allDecksID ? 1 : deckID).desiredRetention
        let buttons = s.answerButtons(days: period.days)
        buttonTotals = (0..<4).map { i in buttons.values.reduce(0) { $0 + $1.counts[i] } }
        totalReviews = s.reviews(days: period.days).count
    }

    func summary(deck: String, period: String) -> String {
        """
        Negoto の学習記録（\(deck)・\(period)）
        今日: \(today.reviews)枚・\(Format.duration(today.seconds))・正答率 \(Format.percent(today.correctRate))
        保持率: \(Format.percent(retention, digits: 1))
        連続学習: \(streak.current)日（最長 \(streak.longest)日）
        カード: 成熟 \(states.mature)・若い \(states.young)・未学習 \(states.new)
        """
    }
}

struct StatsInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                item("保持率", "復習カードに「もう一度」以外で答えた割合（真の保持率）。目標はデッキのオプション（FSRS）の目標保持率です。")
                item("回答ボタンの使用割合", "選んだ期間の、すべての回答に占める各ボタンの割合。")
                item("学習カレンダー", "1日ごとの回答数。色が濃いほど多く学習した日です。")
                item("今後7日間", "その日に期日が来るカード（期限切れは今日に含みます）。")
                item("復習間隔の分布", "復習カードの現在の間隔。右ほど長い間隔です。")
                item("カードの状態", "成熟は間隔が21日以上のカード、若いはそれ未満の復習カードです。")
            }
            .navigationTitle("統計について")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func item(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
