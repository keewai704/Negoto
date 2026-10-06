import Foundation

public enum Rating: Int, CaseIterable, Sendable {
    case again = 1, hard = 2, good = 3, easy = 4
}

/// Scheduling state of a card, modelled after Anki's v3 scheduler (rslib/src/scheduler/states).
public enum CardState: Equatable, Sendable {
    case new
    case learning(LearnState)
    case review(ReviewState)
    case relearning(LearnState, ReviewState)

    public var isLearningLike: Bool {
        switch self {
        case .learning, .relearning: return true
        default: return false
        }
    }
}

public struct LearnState: Equatable, Sendable {
    public var remainingSteps: Int
    public var scheduledSecs: Int
    public var memory: MemoryState?
}

public struct ReviewState: Equatable, Sendable {
    public var scheduledDays: Int
    public var elapsedDays: Int
    public var easeFactor: Double
    public var lapses: Int
    public var leeched: Bool = false
    public var memory: MemoryState?

    var daysLate: Int { elapsedDays - scheduledDays }
}

public struct MemoryState: Equatable, Sendable {
    public var stability: Double
    public var difficulty: Double
}

public struct NextStates: Sendable {
    public var current: CardState
    public var again: CardState
    public var hard: CardState
    public var good: CardState
    public var easy: CardState

    public func state(for rating: Rating) -> CardState {
        switch rating {
        case .again: return again
        case .hard: return hard
        case .good: return good
        case .easy: return easy
        }
    }
}

struct LearningSteps {
    var steps: [Double]  // minutes
    static let day = 86_400

    func index(_ remaining: Int) -> Int {
        let total = steps.count
        return max(0, min(total - (remaining % 1000), total - 1))
    }

    func secs(at i: Int) -> Int? {
        guard i >= 0, i < steps.count else { return nil }
        return Int((steps[i] * 60).rounded())
    }

    var againDelay: Int? { secs(at: 0) }
    var remainingForFailed: Int { steps.count }

    func hardDelay(_ remaining: Int) -> Int? {
        let idx = index(remaining)
        guard let current = secs(at: idx) else { return nil }
        guard idx == 0 else { return current }
        if let next = secs(at: 1) { return roundInDays((current + next) / 2) }
        return roundInDays(min(current * 3 / 2, current + Self.day))
    }

    func goodDelay(_ remaining: Int) -> Int? { secs(at: index(remaining) + 1) }

    func remainingForGood(_ remaining: Int) -> Int { max(0, steps.count - (index(remaining) + 1)) }

    func roundInDays(_ secs: Int) -> Int {
        secs > Self.day ? Int((Double(secs) / Double(Self.day)).rounded()) * Self.day : secs
    }
}

/// Deterministic per-card randomness (so the labels shown on the buttons match what is applied).
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

public struct SchedulerContext {
    public var config: DeckConfig
    public var today: Int
    public var nowSecs: Int64
    public var fsrs: FSRS?
    public var fuzzFactor: Double?
    /// Days since the last review (for FSRS); defaults to the SM-2 derived value.
    public var elapsedDaysOverride: Int?

    var learnSteps: LearningSteps { LearningSteps(steps: config.learnSteps) }
    var relearnSteps: LearningSteps { LearningSteps(steps: config.relearnSteps) }
    var initialEase: Double { config.initialEase >= 1.3 ? config.initialEase : 2.5 }

    public init(config: DeckConfig, today: Int, nowSecs: Int64, fsrs: FSRS? = nil, fuzzFactor: Double? = nil) {
        self.config = config
        self.today = today
        self.nowSecs = nowSecs
        self.fsrs = fsrs
        self.fuzzFactor = fuzzFactor
    }

    func minMax(_ minimum: Int) -> (Int, Int) {
        let maximum = max(config.maximumReviewInterval, 1)
        return (max(1, min(minimum, maximum)), maximum)
    }

    static func fuzzDelta(_ interval: Double) -> Double {
        guard interval >= 2.5 else { return 0 }
        let ranges: [(Double, Double, Double)] = [(2.5, 7.0, 0.15), (7.0, 20.0, 0.1), (20.0, .greatestFiniteMagnitude, 0.05)]
        return ranges.reduce(1.0) { d, r in d + r.2 * max(0, min(interval, r.1) - r.0) }
    }

    static func fuzzBounds(_ interval: Double, minimum: Int, maximum: Int) -> (Int, Int) {
        let minimum = min(minimum, maximum)
        let interval = min(max(interval, Double(minimum)), Double(maximum))
        let delta = fuzzDelta(interval)
        var lower = Int((interval - delta).rounded())
        var upper = Int((interval + delta).rounded())
        lower = min(max(lower, minimum), maximum)
        upper = min(max(upper, minimum), maximum)
        if upper == lower && upper > 2 && upper < maximum { upper = lower + 1 }
        return (lower, upper)
    }

    func withFuzz(_ interval: Double, minimum: Int, maximum: Int) -> Int {
        if let seed = fuzzFactor {
            let (lower, upper) = Self.fuzzBounds(interval, minimum: minimum, maximum: maximum)
            return Int((Double(lower) + seed * Double(1 + upper - lower)).rounded(.down))
        }
        return min(max(Int(interval.rounded()), minimum), maximum)
    }

    func constrainPassing(_ interval: Double, minimum: Int) -> Int {
        let (mn, mx) = minMax(minimum)
        return withFuzz(interval * config.intervalMultiplier, minimum: mn, maximum: mx)
    }
}

public enum Scheduler {
    static let easeAgainDelta = -0.2
    static let easeHardDelta = -0.15
    static let easeEasyDelta = 0.15
    static let minimumEase = 1.3

    // MARK: Card → state

    public static func currentState(of card: Card, today: Int, nowSecs: Int64) -> CardState {
        let memory = card.memoryState.map { MemoryState(stability: $0.stability, difficulty: $0.difficulty) }
        switch card.cardType {
        case .new:
            return .new
        case .learning:
            return .learning(LearnState(remainingSteps: card.left % 1000, scheduledSecs: 0, memory: memory))
        case .review:
            let lastReview = Int(card.due) - card.interval
            return .review(ReviewState(scheduledDays: card.interval, elapsedDays: max(0, today - lastReview),
                                       easeFactor: Double(card.factor) / 1000, lapses: card.lapses, memory: memory))
        case .relearning:
            let review = ReviewState(scheduledDays: card.interval, elapsedDays: 0, easeFactor: Double(card.factor) / 1000,
                                     lapses: card.lapses, memory: memory)
            return .relearning(LearnState(remainingSteps: card.left % 1000, scheduledSecs: 0, memory: memory), review)
        }
    }

    // MARK: Next states

    public static func nextStates(for card: Card, context ctx: SchedulerContext) -> NextStates {
        var current = currentState(of: card, today: ctx.today, nowSecs: ctx.nowSecs)
        // Cards that the queue considers due but whose day-learning due date doesn't match keep their state.
        if case .review(var r) = current, let override = ctx.elapsedDaysOverride { r.elapsedDays = override; current = .review(r) }
        let fsrsMemory = ctx.fsrs.flatMap { fsrs -> FSRSNextMemory? in
            fsrs.nextMemory(card: card, state: current, today: ctx.today, elapsedOverride: ctx.elapsedDaysOverride)
        }
        switch current {
        case .new:
            let learn = LearnState(remainingSteps: ctx.learnSteps.remainingForFailed, scheduledSecs: 0, memory: nil)
            return learningNext(current: current, learn, ctx: ctx, fsrsMemory: fsrsMemory)
        case .learning(let l):
            return learningNext(current: current, l, ctx: ctx, fsrsMemory: fsrsMemory)
        case .review(let r):
            return reviewNext(current: current, r, ctx: ctx, fsrsMemory: fsrsMemory)
        case .relearning(let l, let r):
            return relearningNext(current: current, l, r, ctx: ctx, fsrsMemory: fsrsMemory)
        }
    }

    private static func graduate(_ days: Int, ease: Double, memory: MemoryState?) -> CardState {
        .review(ReviewState(scheduledDays: days, elapsedDays: 0, easeFactor: ease, lapses: 0, memory: memory))
    }

    private static func learningNext(current: CardState, _ l: LearnState, ctx: SchedulerContext, fsrsMemory: FSRSNextMemory?) -> NextStates {
        let steps = ctx.learnSteps
        let (mn, mx) = ctx.minMax(1)
        let goodGrad: Int = {
            if let m = fsrsMemory { return ctx.withFuzz(Double(m.interval(.good, ctx)), minimum: mn, maximum: mx) }
            return ctx.withFuzz(Double(ctx.config.graduatingIntervalGood), minimum: mn, maximum: mx)
        }()
        let again: CardState
        if let delay = steps.againDelay {
            again = .learning(LearnState(remainingSteps: steps.remainingForFailed, scheduledSecs: delay, memory: fsrsMemory?.again))
        } else {
            let days = fsrsMemory.map { ctx.withFuzz(Double($0.interval(.again, ctx)), minimum: mn, maximum: mx) } ?? goodGrad
            again = graduate(days, ease: ctx.initialEase, memory: fsrsMemory?.again)
        }
        let hard: CardState
        if let delay = steps.hardDelay(l.remainingSteps) {
            hard = .learning(LearnState(remainingSteps: l.remainingSteps, scheduledSecs: delay, memory: fsrsMemory?.hard))
        } else {
            let days = fsrsMemory.map { ctx.withFuzz(Double($0.interval(.hard, ctx)), minimum: mn, maximum: mx) } ?? goodGrad
            hard = graduate(days, ease: ctx.initialEase, memory: fsrsMemory?.hard)
        }
        let good: CardState
        if let delay = steps.goodDelay(l.remainingSteps) {
            good = .learning(LearnState(remainingSteps: steps.remainingForGood(l.remainingSteps), scheduledSecs: delay, memory: fsrsMemory?.good))
        } else {
            good = graduate(goodGrad, ease: ctx.initialEase, memory: fsrsMemory?.good)
        }
        var easyDays: Int
        if let m = fsrsMemory {
            easyDays = ctx.withFuzz(Double(m.interval(.easy, ctx)), minimum: mn, maximum: mx)
        } else {
            easyDays = ctx.withFuzz(Double(ctx.config.graduatingIntervalEasy), minimum: mn, maximum: mx)
        }
        if case .review(let g) = good, easyDays <= g.scheduledDays { easyDays = min(g.scheduledDays + 1, mx) }
        let easy = graduate(easyDays, ease: ctx.initialEase, memory: fsrsMemory?.easy)
        return NextStates(current: current, again: again, hard: hard, good: good, easy: easy)
    }

    static func leechThresholdMet(lapses: Int, threshold: Int) -> Bool {
        guard threshold > 0 else { return false }
        let half = max(1, Int((Double(threshold) / 2).rounded(.up)))
        return lapses >= threshold && (lapses - threshold) % half == 0
    }

    private static func reviewNext(current: CardState, _ r: ReviewState, ctx: SchedulerContext, fsrsMemory: FSRSNextMemory?) -> NextStates {
        let cfg = ctx.config
        // Again
        let lapses = r.lapses + 1
        let leeched = leechThresholdMet(lapses: lapses, threshold: cfg.leechThreshold)
        let failDays: Int
        if let m = fsrsMemory {
            let (mn, mx) = ctx.minMax(cfg.minimumLapseInterval)
            failDays = min(max(m.interval(.again, ctx), mn), mx)
        } else {
            failDays = max(max(Int(Double(r.scheduledDays) * cfg.lapseMultiplier), cfg.minimumLapseInterval), 1)
        }
        let againReview = ReviewState(scheduledDays: failDays, elapsedDays: 0,
                                      easeFactor: max(r.easeFactor + easeAgainDelta, minimumEase), lapses: lapses,
                                      leeched: leeched, memory: fsrsMemory?.again)
        let again: CardState
        if let delay = ctx.relearnSteps.againDelay {
            again = .relearning(LearnState(remainingSteps: ctx.relearnSteps.remainingForFailed, scheduledSecs: delay,
                                           memory: fsrsMemory?.again), againReview)
        } else {
            again = .review(againReview)
        }

        // Passing
        let (hardDays, goodDays, easyDays): (Int, Int, Int)
        if let m = fsrsMemory {
            let (mn, mx) = ctx.minMax(1)
            var h = ctx.withFuzz(Double(m.interval(.hard, ctx)), minimum: mn, maximum: mx)
            var g = ctx.withFuzz(Double(m.interval(.good, ctx)), minimum: mn, maximum: mx)
            var e = ctx.withFuzz(Double(m.interval(.easy, ctx)), minimum: mn, maximum: mx)
            h = min(h, g)
            g = min(max(g, h + 1), mx)
            e = min(max(e, g + 1), mx)
            (hardDays, goodDays, easyDays) = (h, g, e)
        } else {
            let currentInterval = Double(r.scheduledDays)
            let daysLate = Double(max(0, r.daysLate))
            let hardFactor = cfg.hardMultiplier
            let hardMin = hardFactor <= 1 ? 0 : r.scheduledDays + 1
            let h = ctx.constrainPassing(currentInterval * hardFactor, minimum: hardMin)
            let goodMin = hardFactor <= 1 ? r.scheduledDays + 1 : h + 1
            let g = ctx.constrainPassing((currentInterval + daysLate / 2) * r.easeFactor, minimum: goodMin)
            let e = ctx.constrainPassing((currentInterval + daysLate) * r.easeFactor * cfg.easyMultiplier, minimum: g + 1)
            (hardDays, goodDays, easyDays) = (h, g, e)
        }
        func passing(_ days: Int, _ delta: Double, _ memory: MemoryState?) -> CardState {
            .review(ReviewState(scheduledDays: days, elapsedDays: 0,
                                easeFactor: max(r.easeFactor + delta, minimumEase), lapses: r.lapses, memory: memory))
        }
        return NextStates(current: current, again: again,
                          hard: passing(hardDays, easeHardDelta, fsrsMemory?.hard),
                          good: passing(goodDays, 0, fsrsMemory?.good),
                          easy: passing(easyDays, easeEasyDelta, fsrsMemory?.easy))
    }

    private static func relearningNext(current: CardState, _ l: LearnState, _ r: ReviewState, ctx: SchedulerContext,
                                       fsrsMemory: FSRSNextMemory?) -> NextStates {
        let steps = ctx.relearnSteps
        let (mn, mx) = ctx.minMax(1)
        func review(_ days: Int, _ memory: MemoryState?) -> CardState {
            var rv = r
            rv.scheduledDays = days
            rv.elapsedDays = 0
            rv.memory = memory
            return .review(rv)
        }
        let fsrsGood = fsrsMemory.map { min(max($0.interval(.good, ctx), mn), mx) }
        let again: CardState
        if let delay = steps.againDelay {
            var rv = r
            rv.elapsedDays = 0
            rv.memory = fsrsMemory?.again
            again = .relearning(LearnState(remainingSteps: steps.remainingForFailed, scheduledSecs: delay, memory: fsrsMemory?.again), rv)
        } else {
            again = review(r.scheduledDays, fsrsMemory?.again)
        }
        let hard: CardState
        if let delay = steps.hardDelay(l.remainingSteps) {
            hard = .relearning(LearnState(remainingSteps: l.remainingSteps, scheduledSecs: delay, memory: fsrsMemory?.hard), r)
        } else {
            hard = review(fsrsGood ?? r.scheduledDays, fsrsMemory?.hard)
        }
        let good: CardState
        if let delay = steps.goodDelay(l.remainingSteps) {
            good = .relearning(LearnState(remainingSteps: steps.remainingForGood(l.remainingSteps), scheduledSecs: delay,
                                          memory: fsrsMemory?.good), r)
        } else {
            good = review(fsrsGood ?? r.scheduledDays, fsrsMemory?.good)
        }
        let easyDays = fsrsMemory.map { max(min(max($0.interval(.easy, ctx), mn), mx), (fsrsGood ?? 0) + 1) } ?? (r.scheduledDays + 1)
        return NextStates(current: current, again: again, hard: hard, good: good, easy: review(easyDays, fsrsMemory?.easy))
    }

    // MARK: Applying

    public struct AnswerResult: Sendable {
        public var card: Card
        public var revlog: RevlogEntry
        public var leeched: Bool
    }

    public static func apply(_ next: NextStates, rating: Rating, to card: Card, context ctx: SchedulerContext,
                             answeredAtMillis: Int64, millisecondsTaken: Int, learnFuzz: Double = 0) -> AnswerResult {
        var c = card
        let state = next.state(for: rating)
        var leeched = false
        var revIvl = 0
        var factor = 0

        func scheduleLearning(_ secs: Int) {
            if secs >= LearningSteps.day {
                c.queue = Card.Queue.dayLearning.rawValue
                c.due = Int64(ctx.today + secs / LearningSteps.day)
            } else {
                // Spread learning cards slightly (up to 25% / 5 minutes) like Anki does.
                let upper = secs + min(Int(Double(secs) * 0.25), 300)
                let fuzzed = upper > secs ? secs + Int(Double(upper - secs) * learnFuzz) : secs
                c.queue = Card.Queue.learning.rawValue
                c.due = ctx.nowSecs + Int64(fuzzed)
            }
        }

        switch state {
        case .new:
            break
        case .learning(let l):
            c.type = Card.CardType.learning.rawValue
            c.left = l.remainingSteps
            scheduleLearning(l.scheduledSecs)
            revIvl = -l.scheduledSecs
            factor = c.factor
        case .relearning(let l, let r):
            c.type = Card.CardType.relearning.rawValue
            c.left = l.remainingSteps
            c.interval = r.scheduledDays
            c.factor = Int((r.easeFactor * 1000).rounded())
            c.lapses = r.lapses
            leeched = r.leeched
            scheduleLearning(l.scheduledSecs)
            revIvl = -l.scheduledSecs
            factor = c.factor
        case .review(let r):
            c.type = Card.CardType.review.rawValue
            c.queue = Card.Queue.review.rawValue
            c.interval = r.scheduledDays
            c.due = Int64(ctx.today + r.scheduledDays)
            c.factor = Int((r.easeFactor * 1000).rounded())
            c.lapses = r.lapses
            c.left = 0
            leeched = r.leeched
            revIvl = r.scheduledDays
            factor = c.factor
        }
        if leeched && ctx.config.leechAction == .suspend {
            c.queue = Card.Queue.suspended.rawValue
        }
        if ctx.fsrs != nil, let memory = memoryOf(state) {
            c.data = updatedData(c.data, memory: memory, retention: ctx.config.desiredRetention, nowSecs: ctx.nowSecs)
        }
        c.reps += 1
        c.mod = ctx.nowSecs
        c.usn = -1

        let lastIvl: Int
        let revType: Int
        switch next.current {
        case .new: lastIvl = 0; revType = 0
        case .learning(let l):
            lastIvl = -(ctx.learnSteps.secs(at: ctx.learnSteps.index(l.remainingSteps)) ?? 60); revType = 0
        case .review(let r): lastIvl = r.scheduledDays; revType = 1
        case .relearning(let l, _):
            lastIvl = -(ctx.relearnSteps.secs(at: ctx.relearnSteps.index(l.remainingSteps)) ?? 600); revType = 2
        }
        let cap = max(ctx.config.capAnswerTimeToSecs, 1) * 1000
        let revlog = RevlogEntry(id: answeredAtMillis, cardId: card.id, usn: -1, ease: rating.rawValue, interval: revIvl,
                                 lastInterval: lastIvl,
                                 factor: factor, time: min(millisecondsTaken, cap), type: revType)
        return AnswerResult(card: c, revlog: revlog, leeched: leeched)
    }

    static func memoryOf(_ state: CardState) -> MemoryState? {
        switch state {
        case .new: return nil
        case .learning(let l): return l.memory
        case .review(let r): return r.memory
        case .relearning(_, let r): return r.memory
        }
    }

    static func updatedData(_ data: String, memory: MemoryState?, retention: Double?, nowSecs: Int64) -> String {
        var obj = (try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any]) ?? [:]
        if let memory {
            obj["s"] = (memory.stability * 10000).rounded() / 10000
            obj["d"] = (memory.difficulty * 1000).rounded() / 1000
            if let retention { obj["dr"] = (retention * 100).rounded() / 100 }
        }
        obj["lrt"] = nowSecs
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return data }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: Labels

    /// Interval in seconds that a state represents (for button labels).
    public static func intervalSecs(_ state: CardState) -> Int {
        switch state {
        case .new: return 0
        case .learning(let l): return l.scheduledSecs
        case .relearning(let l, _): return l.scheduledSecs
        case .review(let r): return r.scheduledDays * LearningSteps.day
        }
    }

    public static func label(for state: CardState, learnAheadSecs: Int) -> String {
        let secs = intervalSecs(state)
        let text = formatInterval(secs)
        if secs < learnAheadSecs, state.isLearningLike { return "<" + text }
        return text
    }

    public static func formatInterval(_ secs: Int) -> String {
        let s = Double(secs)
        let day = 86_400.0
        func fmt1(_ v: Double) -> String {
            let r = (v * 10).rounded() / 10
            return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        }
        if s < 60 { return "\(Int(s.rounded()))s" }
        if s < 3600 { return "\(Int((s / 60).rounded()))m" }
        if s < day { return fmt1(s / 3600) + "h" }
        if s < day * 30 { return "\(Int((s / day).rounded()))d" }
        if s < day * 365 { return fmt1(s / day / 30) + "mo" }
        return fmt1(s / day / 365) + "y"
    }
}
