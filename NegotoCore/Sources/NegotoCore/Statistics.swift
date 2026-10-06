import Foundation

/// Study statistics for a deck (with subdecks) or the whole collection, in the spirit of Anki's stats screen.
public final class CollectionStatistics {
    public struct Review: Sendable {
        /// Days relative to today (0 = today, -1 = yesterday).
        public var day: Int
        public var date: Date
        public var ease: Int
        /// 0 learn, 1 review, 2 relearn, 3 filtered
        public var type: Int
        public var lastInterval: Int
        public var timeMs: Int
    }

    public struct Today: Sendable, Equatable {
        public var reviews = 0
        public var seconds = 0
        public var again = 0
        public var newCards = 0
        public var learn = 0
        public var review = 0
        public var relearn = 0
        public init() {}
        /// Share of answers that weren't "again" (nil when nothing was studied).
        public var correctRate: Double? { reviews == 0 ? nil : Double(reviews - again) / Double(reviews) }
    }

    public struct Day: Sendable, Identifiable, Equatable {
        public var day: Int
        public var learn = 0
        public var review = 0
        public var relearn = 0
        public var seconds = 0
        public var id: Int { day }
        public var total: Int { learn + review + relearn }
    }

    public struct ForecastDay: Sendable, Identifiable, Equatable {
        public var day: Int
        public var learning = 0
        public var young = 0
        public var mature = 0
        public var id: Int { day }
        public var total: Int { learning + young + mature }
    }

    public struct CardStates: Sendable, Equatable {
        public var new = 0
        public var learning = 0
        public var relearning = 0
        public var young = 0
        public var mature = 0
        public var suspended = 0
        public var buried = 0
        public init() {}
        public var total: Int { new + learning + relearning + young + mature + suspended + buried }
    }

    public struct Bucket: Sendable, Identifiable, Equatable {
        public var label: String
        public var count: Int
        public var id: String { label }
    }

    public struct ButtonCounts: Sendable, Equatable {
        public var counts = [0, 0, 0, 0]
        public init() {}
        public var total: Int { counts.reduce(0, +) }
        public var correctRate: Double? { total == 0 ? nil : Double(total - counts[0]) / Double(total) }
    }

    public struct Hour: Sendable, Identifiable, Equatable {
        public var hour: Int
        public var count = 0
        public var correct = 0
        public var id: Int { hour }
        public var correctRate: Double? { count == 0 ? nil : Double(correct) / Double(count) }
    }

    public struct Streak: Sendable, Equatable {
        public var current = 0
        public var longest = 0
        public var daysStudied = 0
        public init(current: Int = 0, longest: Int = 0, daysStudied: Int = 0) {
            self.current = current
            self.longest = longest
            self.daysStudied = daysStudied
        }
    }

    public let collection: AnkiCollection
    public let deckID: Int64
    public let today: Int
    private let cardFilter: String
    private let dayStart: Int64
    private var reviewCache: [Int: [Review]] = [:]

    /// - Parameter deckID: `AnkiCollection.allDecksID` for the whole collection.
    public init(collection: AnkiCollection, deckID: Int64 = AnkiCollection.allDecksID, now: Date = Date()) {
        self.collection = collection
        self.deckID = deckID
        let timing = collection.timingToday(now: now)
        today = timing.daysElapsed
        dayStart = timing.nextDayAt - 86_400
        cardFilter = deckID == AnkiCollection.allDecksID ? "1" : "did IN \(collection.inClause(collection.deckAndChildren(deckID)))"
    }

    // MARK: Review log

    /// Reviews of the last `days` days (nil = all time), excluding manual rescheduling entries.
    public func reviews(days: Int?) -> [Review] {
        let key = days ?? -1
        if let cached = reviewCache[key] { return cached }
        var sql = "SELECT id, ease, type, lastIvl, time FROM revlog WHERE ease > 0"
        var args: [SQLBindable] = []
        if let days {
            sql += " AND id >= ?"
            args.append((dayStart - Int64(days - 1) * 86_400) * 1000)
        }
        if deckID != AnkiCollection.allDecksID { sql += " AND cid IN (SELECT id FROM cards WHERE \(cardFilter))" }
        var out: [Review] = []
        try? collection.db.forEach(sql + " ORDER BY id", args) { row in
            let ms = row[0].int64
            let secs = Double(ms) / 1000
            out.append(Review(day: Int(((secs - Double(dayStart)) / 86_400).rounded(.down)),
                              date: Date(timeIntervalSince1970: secs), ease: row[1].int, type: row[2].int,
                              lastInterval: row[3].int, timeMs: row[4].int))
            return true
        }
        reviewCache[key] = out
        return out
    }

    public func todayStats() -> Today {
        var t = Today()
        for r in reviews(days: 1) where r.day == 0 {
            t.reviews += 1
            t.seconds += r.timeMs / 1000
            if r.ease == 1 { t.again += 1 }
            switch r.type {
            case 0: t.learn += 1; if r.lastInterval == 0 { t.newCards += 1 }
            case 2: t.relearn += 1
            default: t.review += 1
            }
        }
        return t
    }

    /// One entry per day for the last `days` days (oldest first).
    public func daily(days: Int) -> [Day] {
        var byDay = Dictionary(uniqueKeysWithValues: (0..<days).map { (-$0, Day(day: -$0)) })
        for r in reviews(days: days) {
            guard var d = byDay[r.day] else { continue }
            switch r.type {
            case 0: d.learn += 1
            case 2: d.relearn += 1
            default: d.review += 1
            }
            d.seconds += r.timeMs / 1000
            byDay[r.day] = d
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    public func streak() -> Streak {
        let days = Set(reviews(days: nil).map(\.day))
        var s = Streak(daysStudied: days.count)
        var d = days.contains(0) ? 0 : -1
        while days.contains(d) { s.current += 1; d -= 1 }
        var run = 0
        var previous: Int?
        for day in days.sorted() {
            run = (previous.map { day == $0 + 1 } ?? false) ? run + 1 : 1
            s.longest = max(s.longest, run)
            previous = day
        }
        return s
    }

    // MARK: Cards

    /// Cards due in each of the next `days` days (overdue cards count as today).
    public func forecast(days: Int) -> [ForecastDay] {
        var out = (0..<days).map { ForecastDay(day: $0) }
        try? collection.db.forEach("""
            SELECT queue, due, ivl FROM cards WHERE \(cardFilter) AND queue IN (1, 2, 3)
            """) { row in
            let queue = row[0].int, due = row[1].int64, ivl = row[2].int
            let day: Int = queue == 1 ? max(0, Int((due - dayStart) / 86_400)) : max(0, Int(due) - today)
            guard day < days else { return true }
            if queue == 2 {
                if ivl >= 21 { out[day].mature += 1 } else { out[day].young += 1 }
            } else {
                out[day].learning += 1
            }
            return true
        }
        return out
    }

    public func cardStates() -> CardStates {
        var s = CardStates()
        try? collection.db.forEach("SELECT type, queue, ivl FROM cards WHERE \(cardFilter)") { row in
            let type = row[0].int, queue = row[1].int, ivl = row[2].int
            switch queue {
            case -1: s.suspended += 1
            case -2, -3: s.buried += 1
            default:
                switch type {
                case 0: s.new += 1
                case 1: s.learning += 1
                case 3: s.relearning += 1
                default: if ivl >= 21 { s.mature += 1 } else { s.young += 1 }
                }
            }
            return true
        }
        return s
    }

    public func intervalBuckets() -> [Bucket] {
        let edges: [(String, Int, Int)] = [("1日", 1, 1), ("2–3日", 2, 3), ("4–7日", 4, 7), ("1–2週", 8, 14),
                                           ("2週–1月", 15, 30), ("1–3月", 31, 90), ("3–6月", 91, 180),
                                           ("6月–1年", 181, 365), ("1年以上", 366, Int.max)]
        var counts = [Int](repeating: 0, count: edges.count)
        try? collection.db.forEach("SELECT ivl FROM cards WHERE \(cardFilter) AND type IN (2, 3) AND ivl > 0") { row in
            let ivl = row[0].int
            if let i = edges.firstIndex(where: { ivl >= $0.1 && ivl <= $0.2 }) { counts[i] += 1 }
            return true
        }
        return zip(edges, counts).map { Bucket(label: $0.0, count: $1) }
    }

    /// FSRS difficulty (when available) or SM-2 ease, as a distribution.
    public func difficultyBuckets() -> (title: String, buckets: [Bucket]) {
        var difficulties: [Double] = []
        var eases: [Int] = []
        try? collection.db.forEach("SELECT factor, data FROM cards WHERE \(cardFilter) AND type IN (2, 3)") { row in
            if let obj = try? JSONSerialization.jsonObject(with: Data(row[1].string.utf8)) as? [String: Any],
               let d = (obj["d"] as? NSNumber)?.doubleValue {
                difficulties.append(d)
            }
            if row[0].int > 0 { eases.append(row[0].int) }
            return true
        }
        if collection.fsrsEnabled && !difficulties.isEmpty {
            var counts = [Int](repeating: 0, count: 10)
            for d in difficulties { counts[min(9, max(0, Int(((d - 1) / 9 * 10).rounded(.down))))] += 1 }
            return ("難易度（FSRS）", counts.enumerated().map { Bucket(label: "\($0.offset * 10)%", count: $0.element) })
        }
        let edges = [(130, 170), (170, 210), (210, 250), (250, 290), (290, 330), (330, 1000)]
        var counts = [Int](repeating: 0, count: edges.count)
        for e in eases {
            let pct = e / 10
            if let i = edges.firstIndex(where: { pct >= $0.0 && pct < $0.1 }) { counts[i] += 1 }
        }
        return ("易しさ（SM-2）", zip(edges, counts).map { Bucket(label: $0.1 >= 1000 ? "\($0.0)%+" : "\($0.0)%", count: $1) })
    }

    // MARK: Answers

    public enum Category: String, CaseIterable, Sendable { case learning, young, mature }

    public func answerButtons(days: Int?) -> [Category: ButtonCounts] {
        var out: [Category: ButtonCounts] = [.learning: .init(), .young: .init(), .mature: .init()]
        for r in reviews(days: days) where (1...4).contains(r.ease) {
            let cat: Category = r.type == 1 ? (r.lastInterval >= 21 ? .mature : .young) : .learning
            out[cat]!.counts[r.ease - 1] += 1
        }
        return out
    }

    /// "True retention": share of review answers that weren't "again", for young and mature cards.
    public func retention(days: Int?) -> (young: ButtonCounts, mature: ButtonCounts) {
        let b = answerButtons(days: days)
        return (b[.young] ?? .init(), b[.mature] ?? .init())
    }

    public func hourly(days: Int?) -> [Hour] {
        var out = (0..<24).map { Hour(hour: $0) }
        let cal = Calendar.current
        for r in reviews(days: days) {
            let h = cal.component(.hour, from: r.date)
            out[h].count += 1
            if r.ease > 1 { out[h].correct += 1 }
        }
        return out
    }

    /// Reviews per day for a calendar heatmap: day offset → count, for the last `days` days.
    public func heatmap(days: Int) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for r in reviews(days: days) { out[r.day, default: 0] += 1 }
        return out
    }

    // MARK: Summaries used by the redesigned screens

    public struct RetentionPoint: Sendable, Identifiable, Equatable {
        /// Day offset of the first day of the bucket (0 = today, negative = past).
        public var startDay: Int
        public var reviews: Int
        public var passed: Int
        public var id: Int { startDay }
        public var rate: Double? { reviews == 0 ? nil : Double(passed) / Double(reviews) }
    }

    /// Pass rate of review-card answers ("true retention") in `buckets` equal slices of the period.
    public func retentionTrend(days: Int, buckets: Int = 12) -> [RetentionPoint] {
        let n = max(1, buckets)
        let size = max(1, Int((Double(days) / Double(n)).rounded(.up)))
        var points = (0..<n).map { i in RetentionPoint(startDay: -(n - i) * size + 1, reviews: 0, passed: 0) }
        for r in reviews(days: size * n) where r.type == 1 && (1...4).contains(r.ease) {
            let index = n - 1 - min(n - 1, (-r.day) / size)
            guard index >= 0 && index < n else { continue }
            points[index].reviews += 1
            if r.ease > 1 { points[index].passed += 1 }
        }
        return points
    }

    /// Pass rate of review answers in the period.
    public func trueRetention(days: Int?) -> Double? {
        var total = 0, passed = 0
        for r in reviews(days: days) where r.type == 1 && (1...4).contains(r.ease) {
            total += 1
            if r.ease > 1 { passed += 1 }
        }
        return total == 0 ? nil : Double(passed) / Double(total)
    }

    /// Average seconds spent on one answer recently (8 seconds when there is no history).
    public func secondsPerAnswer() -> Double {
        let recent = reviews(days: 30)
        guard recent.count >= 5 else { return 8 }
        let total = recent.reduce(0) { $0 + min(60_000, $1.timeMs) }
        return max(2, Double(total) / Double(recent.count) / 1000)
    }

    /// When a card of this deck was last answered.
    public func lastStudied() -> Date? {
        var sql = "SELECT max(id) FROM revlog WHERE ease > 0"
        if deckID != AnkiCollection.allDecksID { sql += " AND cid IN (SELECT id FROM cards WHERE \(cardFilter))" }
        guard let v = try? collection.db.scalar(sql), !v.isNull else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(v.int64) / 1000)
    }

    /// Review intervals by day (1…`maxDays`, the last bucket collects everything longer).
    public func intervalDistribution(maxDays: Int = 180, bucketCount: Int = 24) -> [Bucket] {
        let size = max(1, Int((Double(maxDays) / Double(bucketCount)).rounded(.up)))
        var counts = [Int](repeating: 0, count: bucketCount)
        try? collection.db.forEach("SELECT ivl FROM cards WHERE \(cardFilter) AND type IN (2, 3) AND ivl > 0") { row in
            counts[min(bucketCount - 1, (row[0].int - 1) / size)] += 1
            return true
        }
        return counts.enumerated().map { i, c in
            Bucket(label: i == bucketCount - 1 ? "\(i * size + 1)日+" : "\(i * size + 1)日", count: c)
        }
    }
}
