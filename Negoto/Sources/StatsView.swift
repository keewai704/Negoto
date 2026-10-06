import Charts
import NegotoCore
import SwiftUI

/// Statistics for the whole collection or one deck: today, streak, calendar, review volume,
/// forecast, card states, intervals, retention, answer buttons, time of day and difficulty.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var deckID: Int64 = AnkiCollection.allDecksID
    @State private var period: Period = .month
    @State private var data: StatsData?
    @State private var width: CGFloat = 0
    private var layout: LayoutWidth { LayoutWidth(width) }

    enum Period: Int, CaseIterable, Identifiable {
        case month = 30, quarter = 90, year = 365, all = 0
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .month: return "1か月"
            case .quarter: return "3か月"
            case .year: return "1年"
            case .all: return "すべて"
            }
        }
        var days: Int? { self == .all ? nil : rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    controls
                    if let data {
                        if data.totalReviews == 0 && data.states.total == 0 {
                            ContentUnavailableView("まだデータがありません", systemImage: "chart.bar",
                                                   description: Text("デッキを読み込んで学習すると、ここに統計が表示されます。"))
                        } else {
                            content(data)
                        }
                    } else {
                        ProgressView().padding(40)
                    }
                }
                .readWidth(into: $width)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, 16)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("統計")
            .task(id: Key(deckID: deckID, period: period, revision: model.revision)) { load() }
        }
    }

    struct Key: Equatable {
        var deckID: Int64
        var period: Period
        var revision: Int
    }

    private func load() {
        guard let col = model.collectionHandle else { return }
        if deckID != AnkiCollection.allDecksID && col.decks[deckID] == nil { deckID = AnkiCollection.allDecksID }
        data = StatsData(col, deckID: deckID, period: period)
    }

    @ViewBuilder
    private var controls: some View {
        let stack = layout == .compact ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 16))
        stack {
            Menu {
                Picker("対象", selection: $deckID) {
                    Text("すべてのデッキ").tag(AnkiCollection.allDecksID)
                    ForEach(model.collectionHandle?.sortedDecks.filter { !$0.isFiltered } ?? []) { d in
                        Text(String(repeating: "　", count: d.depth) + d.baseName).tag(d.id)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "square.stack")
                    Text(deckID == AnkiCollection.allDecksID ? "すべてのデッキ" : (model.collectionHandle?.decks[deckID]?.name ?? ""))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassBackground(in: Capsule(), interactive: true)
            }
            Picker("期間", selection: $period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: layout == .compact ? .infinity : 420)
        }
        .frame(maxWidth: .infinity, alignment: layout == .compact ? .center : .leading)
    }

    private var chartColumns: [GridItem] {
        let n = layout == .compact ? 1 : (layout == .medium ? 2 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: n)
    }

    @ViewBuilder
    private func content(_ d: StatsData) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: layout.tileColumns), spacing: 12) {
            StatTile(icon: "rectangle.stack.fill", title: "今日学習したカード", value: "\(d.today.reviews)", tint: Theme.new)
            StatTile(icon: "clock.fill", title: "今日の学習時間", value: Format.duration(d.today.seconds), tint: Theme.nightBottom)
            StatTile(icon: "flame.fill", title: "連続学習日数", value: "\(d.streak.current)日", tint: Theme.learning)
            StatTile(icon: "trophy.fill", title: "最長連続記録", value: "\(d.streak.longest)日", tint: Theme.moon)
        }

        ChartCard(title: "学習カレンダー", subtitle: "過去1年・\(d.streak.daysStudied)日学習") {
            ActivityHeatmap(counts: d.heatmap, weeks: max(8, min(53, Int((width - 40) / 15))), cell: 12)
        }

        LazyVGrid(columns: chartColumns, spacing: 16) {
            ChartCard(title: "学習量", subtitle: "合計\(d.totalReviews)回・1日平均\(d.averagePerDay)回・\(Format.duration(d.totalSeconds))") {
                Chart(d.daily) { day in
                    ForEach(day.series, id: \.0) { s in
                        BarMark(x: .value("日付", d.date(day.day), unit: .day), y: .value("回数", s.1))
                            .foregroundStyle(by: .value("種類", s.0))
                    }
                }
                .chartForegroundStyleScale(["学習": Theme.new, "復習": Theme.review, "再学習": Theme.learning])
                .chartLegend(position: .bottom)
                .frame(height: 200)
            }

            ChartCard(title: "今後の予定", subtitle: "明日\(d.forecast.count > 1 ? d.forecast[1].total : 0)枚・30日で\(d.forecast.reduce(0) { $0 + $1.total })枚") {
                Chart(d.forecast) { f in
                    BarMark(x: .value("日", f.day), y: .value("枚数", f.learning)).foregroundStyle(by: .value("種類", "学習中"))
                    BarMark(x: .value("日", f.day), y: .value("枚数", f.young)).foregroundStyle(by: .value("種類", "復習中"))
                    BarMark(x: .value("日", f.day), y: .value("枚数", f.mature)).foregroundStyle(by: .value("種類", "定着"))
                }
                .chartForegroundStyleScale(["学習中": Theme.learning, "復習中": Theme.young, "定着": Theme.mature])
                .chartXAxisLabel("何日後")
                .chartLegend(position: .bottom)
                .frame(height: 200)
            }

            ChartCard(title: "カードの状態", subtitle: "全\(d.states.total)枚") {
                HStack(spacing: 18) {
                    Chart(d.stateParts, id: \.0) { part in
                        SectorMark(angle: .value("枚数", part.1), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(part.2)
                            .cornerRadius(3)
                    }
                    .frame(width: 140, height: 140)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(Format.percent(d.states.total == 0 ? nil : Double(d.states.mature) / Double(d.states.total)))
                                .font(.title3.weight(.bold))
                            Text("定着").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(d.stateParts, id: \.0) { part in
                            HStack(spacing: 6) {
                                Circle().fill(part.2).frame(width: 9, height: 9)
                                Text(part.0).font(.subheadline)
                                Spacer()
                                Text("\(part.1)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            ChartCard(title: "定着率", subtitle: "復習で「もう一度」以外を押した割合") {
                HStack(spacing: 14) {
                    RetentionGauge(title: "復習中（21日未満）", counts: d.retention.young, color: Theme.young)
                    RetentionGauge(title: "定着（21日以上）", counts: d.retention.mature, color: Theme.mature)
                }
            }

            ChartCard(title: "間隔", subtitle: "復習カードの次回までの間隔") {
                Chart(d.intervals) { b in
                    BarMark(x: .value("間隔", b.label), y: .value("枚数", b.count))
                        .foregroundStyle(Theme.nightBottom.gradient)
                        .cornerRadius(4)
                }
                .frame(height: 180)
            }

            ChartCard(title: "解答ボタン", subtitle: "期間内に押したボタンの割合") {
                Chart(d.buttonRows, id: \.id) { row in
                    BarMark(x: .value("割合", row.share), y: .value("種類", row.category))
                        .foregroundStyle(by: .value("ボタン", row.button))
                }
                .chartForegroundStyleScale(["もう一度": Theme.color(for: .again), "難しい": Theme.color(for: .hard),
                                            "正解": Theme.color(for: .good), "簡単": Theme.color(for: .easy)])
                .chartXAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
                .chartLegend(position: .bottom)
                .frame(height: 160)
            }

            ChartCard(title: "時間帯", subtitle: "学習した時刻と正答率") {
                Chart(d.hours) { h in
                    BarMark(x: .value("時", h.hour), y: .value("回数", h.count))
                        .foregroundStyle(Color.accentColor.opacity(0.35 + 0.65 * (h.correctRate ?? 0)))
                }
                .chartXScale(domain: 0...23)
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisGridLine()
                    AxisValueLabel { if let i = v.as(Int.self) { Text("\(i)時") } }
                } }
                .frame(height: 160)
            }

            ChartCard(title: d.difficulty.title, subtitle: "復習カードの分布") {
                Chart(d.difficulty.buckets) { b in
                    BarMark(x: .value("値", b.label), y: .value("枚数", b.count))
                        .foregroundStyle(Theme.learning.gradient)
                        .cornerRadius(4)
                }
                .frame(height: 160)
            }
        }
    }
}

struct ChartCard<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: title, subtitle: subtitle)
                content
            }
        }
    }
}

struct RetentionGauge: View {
    var title: String
    var counts: CollectionStatistics.ButtonCounts
    var color: Color

    var body: some View {
        VStack(spacing: 8) {
            Gauge(value: counts.correctRate ?? 0) {
                EmptyView()
            } currentValueLabel: {
                Text(Format.percent(counts.correctRate)).font(.headline)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(color)
            .scaleEffect(1.3)
            .frame(height: 76)
            Text(title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("\(counts.total)回").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Everything shown on the statistics screen, computed once per deck/period.
struct StatsData {
    struct DaySeries: Identifiable {
        var day: Int
        var series: [(String, Int)]
        var id: Int { day }
    }

    struct ButtonRow: Identifiable {
        var category: String
        var button: String
        var share: Double
        var id: String { category + button }
    }

    var today: CollectionStatistics.Today
    var streak: CollectionStatistics.Streak
    var heatmap: [Int: Int]
    var daily: [DaySeries]
    var totalReviews: Int
    var totalSeconds: Int
    var averagePerDay: Int
    var forecast: [CollectionStatistics.ForecastDay]
    var states: CollectionStatistics.CardStates
    var intervals: [CollectionStatistics.Bucket]
    var retention: (young: CollectionStatistics.ButtonCounts, mature: CollectionStatistics.ButtonCounts)
    var buttonRows: [ButtonRow]
    var hours: [CollectionStatistics.Hour]
    var difficulty: (title: String, buckets: [CollectionStatistics.Bucket])
    private let startOfToday = Calendar.current.startOfDay(for: Date())

    var stateParts: [(String, Int, Color)] {
        [("新規", states.new, Theme.new), ("学習中", states.learning + states.relearning, Theme.learning),
         ("復習中", states.young, Theme.young), ("定着", states.mature, Theme.mature),
         ("保留", states.suspended, Theme.suspended), ("延期", states.buried, Theme.buried)].filter { $0.1 > 0 }
    }

    func date(_ day: Int) -> Date { Calendar.current.date(byAdding: .day, value: day, to: startOfToday) ?? startOfToday }

    init(_ col: AnkiCollection, deckID: Int64, period: StatsView.Period) {
        let s = CollectionStatistics(collection: col, deckID: deckID)
        today = s.todayStats()
        streak = s.streak()
        heatmap = s.heatmap(days: 53 * 7)
        let all = s.reviews(days: period.days)
        let spanDays: Int = {
            if let days = period.days { return days }
            return max(30, min(3650, -(all.first?.day ?? 0) + 1))
        }()
        let days = s.daily(days: spanDays)
        daily = days.map { DaySeries(day: $0.day, series: [("学習", $0.learn), ("復習", $0.review), ("再学習", $0.relearn)]) }
        totalReviews = all.count
        totalSeconds = all.reduce(0) { $0 + $1.timeMs / 1000 }
        let studiedDays = Set(all.map(\.day)).count
        averagePerDay = studiedDays == 0 ? 0 : all.count / studiedDays
        forecast = s.forecast(days: 30)
        states = s.cardStates()
        intervals = s.intervalBuckets()
        retention = s.retention(days: period.days)
        let buttons = s.answerButtons(days: period.days)
        var rows: [ButtonRow] = []
        for (cat, label) in [(CollectionStatistics.Category.learning, "学習"), (.young, "復習中"), (.mature, "定着")] {
            let b = buttons[cat] ?? .init()
            guard b.total > 0 else { continue }
            for (i, rating) in Rating.allCases.enumerated() {
                rows.append(ButtonRow(category: label, button: Theme.title(for: rating), share: Double(b.counts[i]) / Double(b.total)))
            }
        }
        buttonRows = rows
        hours = s.hourly(days: period.days)
        difficulty = s.difficultyBuckets()
    }
}
