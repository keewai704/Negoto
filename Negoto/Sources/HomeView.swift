import NegotoCore
import SwiftUI

/// "Today": what is left to study, today's progress, streak and recent activity.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Binding var showImporter: Bool
    var openDecks: () -> Void
    @State private var summary = HomeSummary()

    @State private var width: CGFloat = 0

    private var layout: LayoutWidth { LayoutWidth(width) }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if model.isEmpty {
                        WelcomeCard(showImporter: $showImporter)
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                    } else {
                        AdaptiveColumns(width: width, sideBySide: layout == .wide, leadingFraction: 0.44) {
                            TodayHero(counts: model.totalCounts, studiedToday: summary.today.reviews) {
                                model.startStudy(.all)
                            }
                            metrics(columns: layout == .medium ? 4 : 2)
                            if layout == .wide { heatmapCard(weeksFor: (width - 20) * 0.44) }
                        } trailing: {
                            dueDecks(columns: layout == .compact ? 1 : 2)
                            if layout != .wide { heatmapCard(weeksFor: width) }
                        }
                    }
                }
                .readWidth(into: $width)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, 12)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Self.greeting())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SyncToolbarButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Label("デッキを読み込む", systemImage: "plus") }
                        .keyboardShortcut("o", modifiers: .command)
                }
            }
            .refreshable {
                model.refreshCounts()
                model.sync.requestSync(force: true)
            }
            .onAppear(perform: reload)
            .onChange(of: model.revision) { _, _ in reload() }
        }
    }

    private func reload() {
        guard let col = model.collectionHandle else { return }
        summary = HomeSummary(col)
    }

    private func heatmapCard(weeksFor available: CGFloat) -> some View {
        let weeks = max(8, min(53, Int((available - 40) / 16)))
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "最近の学習", subtitle: "過去\(weeks)週間・連続\(summary.streak.current)日")
                ActivityHeatmap(counts: summary.heatmap, weeks: weeks)
            }
        }
    }

    private func metrics(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            StatTile(icon: "rectangle.stack.fill", title: "今日学習したカード", value: "\(summary.today.reviews)", tint: Theme.new)
            StatTile(icon: "clock.fill", title: "今日の学習時間", value: Format.duration(summary.today.seconds), tint: Theme.nightBottom)
            StatTile(icon: "checkmark.seal.fill", title: "今日の正答率", value: Format.percent(summary.today.correctRate), tint: Theme.review)
            StatTile(icon: "flame.fill", title: "連続学習日数", value: "\(summary.streak.current)日", tint: Theme.learning)
        }
    }

    @ViewBuilder
    private func dueDecks(columns: Int) -> some View {
        let decks = model.deckTree.filter { $0.counts.total > 0 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "学習待ちのデッキ", subtitle: decks.isEmpty ? "今日学習するデッキはありません" : "\(decks.count)個のデッキ")
                Button("すべて表示", action: openDecks).font(.subheadline)
            }
            if !decks.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(decks) { node in
                        Button { model.startStudy(node.ref) } label: { DueDeckTile(node: node) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    static func greeting(now: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 4..<11: return "おはようございます"
        case 11..<18: return "こんにちは"
        default: return "こんばんは"
        }
    }
}

struct HomeSummary {
    var today = CollectionStatistics.Today()
    var streak = CollectionStatistics.Streak()
    var heatmap: [Int: Int] = [:]

    init() {}

    init(_ col: AnkiCollection) {
        let stats = CollectionStatistics(collection: col)
        today = stats.todayStats()
        streak = stats.streak()
        heatmap = stats.heatmap(days: 53 * 7)
    }
}

/// The night-sky card at the top of Home.
struct TodayHero: View {
    var counts: DeckCounts
    var studiedToday: Int
    var start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date(), format: .dateTime.month().day().weekday(.wide))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(counts.total > 0 ? "今日の残り" : "今日の学習は完了")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: counts.total > 0 ? "moon.stars.fill" : "moon.zzz.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.moon)
                    .shadow(color: Theme.moon.opacity(0.5), radius: 12)
            }
            if counts.total > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(counts.total)")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    Text("枚").font(.title3.weight(.semibold))
                }
                .foregroundStyle(.white)
                HStack(spacing: 18) {
                    legend("新規", counts.new, Theme.new)
                    legend("学習中", counts.learning, Theme.learning)
                    legend("復習", counts.review, Theme.review)
                }
                Button(action: start) {
                    Label("すべてのデッキを学習", systemImage: "play.fill").wideLabel()
                }
                .primaryActionStyle(onNight: true)
            } else {
                Text(studiedToday > 0 ? "今日は\(studiedToday)枚学習しました。また明日。" : "今日学習するカードはありません。")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(22)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.night)
                StarField().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }

    private func legend(_ title: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.white.opacity(0.75))
            Text("\(n)").fontWeight(.semibold).foregroundStyle(.white).monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// A few faint stars, deterministic so they don't jump around.
struct StarField: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 7)
            for _ in 0..<26 {
                let x = rng.next() * size.width, y = rng.next() * size.height
                let r = 0.6 + rng.next() * 1.4
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.15 + rng.next() * 0.35)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 33) / CGFloat(1 << 31)
    }
}

struct DueDeckTile: View {
    var node: DeckNode

    var body: some View {
        Surface(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: node.children != nil ? "square.stack.3d.up.fill" : "rectangle.portrait.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.night, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.deck.baseName).font(.headline).lineLimit(1)
                    DuePills(counts: node.counts, size: .small)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

struct WelcomeCard: View {
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.moon)
                .padding(.top, 8)
            Text("Negotoへようこそ")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text("Ankiのデッキ（.apkg / .colpkg）を読み込むと、Ankiと同じ表示・同じスケジュールで学習できます。AnkiWebの共有デッキもそのまま使えます。")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button { showImporter = true } label: {
                Label("デッキを読み込む", systemImage: "tray.and.arrow.down.fill").wideLabel()
            }
            .primaryActionStyle(onNight: true)
            Text("ファイルアプリや他のアプリの「共有」から開いても読み込めます。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.night)
                StarField().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }
}

/// GitHub-style calendar of reviews per day (columns are weeks, newest on the right).
struct ActivityHeatmap: View {
    var counts: [Int: Int]
    var weeks: Int
    var cell: CGFloat = 13

    var body: some View {
        let maxCount = max(1, counts.values.max() ?? 1)
        let weekday = (Calendar.current.component(.weekday, from: Date()) + 5) % 7  // Monday = 0
        VStack(alignment: .leading, spacing: 8) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let offset = -((weeks - 1 - w) * 7 + (weekday - d))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(offset > 0 ? nil : counts[offset] ?? 0, max: maxCount))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        HStack(spacing: 4) {
            Text("少").font(.caption2).foregroundStyle(.secondary)
            ForEach([0, 1, 3, 6, 10], id: \.self) { v in
                RoundedRectangle(cornerRadius: 2).fill(color(v, max: 10)).frame(width: 10, height: 10)
            }
            Text("多").font(.caption2).foregroundStyle(.secondary)
        }
        }
    }

    private func color(_ n: Int?, max: Int) -> Color {
        guard let n else { return .clear }
        if n == 0 { return Color(.tertiarySystemFill) }
        let level = min(1, 0.25 + 0.75 * Double(n) / Double(max))
        return Color.accentColor.opacity(level)
    }
}
