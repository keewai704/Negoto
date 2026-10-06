import Foundation

public struct DeckCounts: Hashable, Sendable {
    public var new: Int
    public var learning: Int
    public var review: Int
    public var total: Int { new + learning + review }

    public init(new: Int = 0, learning: Int = 0, review: Int = 0) {
        self.new = new
        self.learning = learning
        self.review = review
    }
}

public struct QueuedCard: Sendable {
    public enum Kind: Sendable { case new, learning, review }
    public var card: Card
    public var kind: Kind

    public init(card: Card, kind: Kind) {
        self.card = card
        self.kind = kind
    }
}

/// Daily limits for every deck, computed from one query over today's reviews.
struct DayLimits {
    let collection: AnkiCollection
    let timing: SchedTimingToday
    private var studied: [Int64: (new: Int, review: Int)] = [:]

    init(_ collection: AnkiCollection, timing: SchedTimingToday) {
        self.collection = collection
        self.timing = timing
        var studied: [Int64: (new: Int, review: Int)] = [:]
        try? collection.db.forEach("""
            SELECT c.did, sum(CASE WHEN r.type = 0 AND r.lastIvl = 0 THEN 1 ELSE 0 END), sum(CASE WHEN r.type = 1 THEN 1 ELSE 0 END)
            FROM revlog r JOIN cards c ON c.id = r.cid WHERE r.id > ? GROUP BY c.did
            """, [collection.dayStartMillis(timing)]) { row in
            studied[row[0].int64] = (row[1].int, row[2].int); return true
        }
        self.studied = studied
    }

    private func studiedIn(_ deckId: Int64) -> (new: Int, review: Int) {
        collection.deckAndChildren(deckId).reduce((0, 0)) { acc, id in
            let s = studied[id] ?? (0, 0)
            return (acc.0 + s.new, acc.1 + s.review)
        }
    }

    /// Remaining limits for a deck, honouring the limits of the deck itself and each of its parents.
    func remaining(for deckId: Int64) -> (new: Int, review: Int) {
        if deckId == AnkiCollection.allDecksID {
            return collection.rootDecks.reduce((0, 0)) { acc, d in
                let r = remaining(for: d.id)
                return (acc.0 + r.new, acc.1 + r.review)
            }
        }
        var newLimit = Int.max, reviewLimit = Int.max
        var name: String? = collection.decks[deckId]?.name
        while let n = name {
            if let d = collection.deck(named: n) {
                let lim = collection.limits(for: d.id)
                let done = studiedIn(d.id)
                newLimit = min(newLimit, max(0, lim.new - done.new))
                reviewLimit = min(reviewLimit, max(0, lim.review - done.review))
            }
            let comps = n.components(separatedBy: "::")
            name = comps.count > 1 ? comps.dropLast().joined(separator: "::") : nil
        }
        return (newLimit == Int.max ? 0 : newLimit, reviewLimit == Int.max ? 0 : reviewLimit)
    }
}

extension AnkiCollection {
    /// Pseudo deck id meaning "every deck".
    public static let allDecksID: Int64 = 0

    /// Start of the current scheduling day in Unix milliseconds.
    func dayStartMillis(_ timing: SchedTimingToday) -> Int64 { (timing.nextDayAt - 86_400) * 1000 }

    func inClause(_ ids: [Int64]) -> String { "(" + (ids.isEmpty ? "-1" : ids.map(String.init).joined(separator: ",")) + ")" }

    func deck(named name: String) -> Deck? { decks.values.first { $0.name == name } }

    /// Top-level decks (excluding filtered decks).
    public var rootDecks: [Deck] { decks.values.filter { !$0.isFiltered && $0.parentName == nil } }

    func limits(for deckId: Int64) -> (new: Int, review: Int) {
        let conf = deckConfig(for: deckId)
        let deck = decks[deckId]
        return (deck?.newLimit ?? conf.newPerDay, deck?.reviewLimit ?? conf.reviewsPerDay)
    }

    func remainingLimits(for deckId: Int64, timing: SchedTimingToday) -> (new: Int, review: Int) {
        DayLimits(self, timing: timing).remaining(for: deckId)
    }

    public func counts(for deckId: Int64, now: Date = Date()) -> DeckCounts {
        let timing = timingToday(now: now)
        return counts(for: deckId, now: now, limits: DayLimits(self, timing: timing))
    }

    func counts(for deckId: Int64, now: Date, limits: DayLimits) -> DeckCounts {
        if deckId == Self.allDecksID {
            return rootDecks.reduce(DeckCounts()) { acc, d in
                let c = counts(for: d.id, now: now, limits: limits)
                return DeckCounts(new: acc.new + c.new, learning: acc.learning + c.learning, review: acc.review + c.review)
            }
        }
        let timing = limits.timing
        let ids = deckAndChildren(deckId)
        let decksSQL = inClause(ids)
        let nowSecs = Int64(now.timeIntervalSince1970)
        let cutoff = nowSecs + Int64(learnAheadSeconds)
        let learning = (try? db.scalar("""
            SELECT (SELECT count() FROM cards WHERE did IN \(decksSQL) AND queue = 1 AND due < ?)
                 + (SELECT count() FROM cards WHERE did IN \(decksSQL) AND queue = 3 AND due <= ?)
            """, [max(cutoff, timing.nextDayAt), timing.daysElapsed]).int) ?? 0
        let (newLeft, revLeft) = limits.remaining(for: deckId)
        var available: [Int64: (new: Int, review: Int)] = [:]
        try? db.forEach("""
            SELECT did, sum(CASE WHEN queue = 0 THEN 1 ELSE 0 END), sum(CASE WHEN queue = 2 AND due <= ? THEN 1 ELSE 0 END)
            FROM cards WHERE did IN \(decksSQL) GROUP BY did
            """, [timing.daysElapsed]) { row in
            available[row[0].int64] = (row[1].int, row[2].int); return true
        }
        // Each subdeck is also bounded by its own limit.
        var newAvail = 0, revAvail = 0
        for (id, a) in available where a.new > 0 || a.review > 0 {
            let own = id == deckId ? (newLeft, revLeft) : limits.remaining(for: id)
            newAvail += min(a.new, own.0)
            revAvail += min(a.review, own.1)
        }
        return DeckCounts(new: min(newAvail, newLeft), learning: learning, review: min(revAvail, revLeft))
    }

    /// Days since the card was last reviewed, as FSRS sees it: from the "lrt" timestamp Anki stores
    /// in the card, else from the review log, else 0 (Anki's behaviour without history).
    public func daysSinceLastReview(_ card: Card, now: Date = Date()) -> Int {
        var lastSecs = card.lastReviewTime
        if lastSecs == nil, let ms = try? db.scalar("SELECT max(id) FROM revlog WHERE cid = ? AND ease > 0", [card.id]), !ms.isNull {
            lastSecs = ms.int64 / 1000
        }
        guard let last = lastSecs else { return 0 }
        let today = timingToday(now: now).daysElapsed
        let thatDay = timingToday(now: Date(timeIntervalSince1970: TimeInterval(last))).daysElapsed
        return max(0, today - thatDay)
    }

    public func totalCards(in deckId: Int64) -> Int {
        (try? db.scalar("SELECT count() FROM cards WHERE did IN \(inClause(deckAndChildren(deckId)))").int) ?? 0
    }
}

/// A study session over one deck (and its subdecks).
public final class StudySession {
    public let collection: AnkiCollection
    public let deckId: Int64
    public private(set) var counts = DeckCounts()
    private var seenNotes = Set<Int64>()
    private var answeredInSession = 0
    private var undoStack: [(card: Card, revlogId: Int64, note: Note?, answeredMod: Int64)] = []

    public init(collection: AnkiCollection, deckId: Int64) {
        self.collection = collection
        self.deckId = deckId
        refreshCounts()
    }

    public func refreshCounts(now: Date = Date()) {
        counts = collection.counts(for: deckId, now: now)
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    private var deckList: String { "(" + collection.deckAndChildren(deckId).map(String.init).joined(separator: ",") + ")" }

    public func nextCard(now: Date = Date()) -> QueuedCard? {
        refreshCounts(now: now)
        let timing = collection.timingToday(now: now)
        let nowSecs = Int64(now.timeIntervalSince1970)
        let decks = deckList
        let db = collection.db

        func first(_ sql: String, _ args: [SQLBindable], kind: QueuedCard.Kind, burySiblings: Bool) -> QueuedCard? {
            var found: QueuedCard?
            try? db.forEach("SELECT \(AnkiCollection.cardColumns) FROM cards WHERE \(sql) LIMIT 200", args) { row in
                let card = AnkiCollection.card(from: row)
                if burySiblings && seenNotes.contains(card.noteId) { return true }
                found = QueuedCard(card: card, kind: kind)
                return false
            }
            return found
        }
        let conf = collection.deckConfig(for: deckId)
        // Only take new/review cards from decks whose own (and parents') daily limit isn't used up.
        let limits = DayLimits(collection, timing: timing)
        let ids = collection.deckAndChildren(deckId)
        let newDecks = collection.inClause(ids.filter { limits.remaining(for: $0).new > 0 })
        let reviewDecks = collection.inClause(ids.filter { limits.remaining(for: $0).review > 0 })

        // 1. Learning cards that are due now.
        if let c = first("did IN \(decks) AND queue = 1 AND due <= ? ORDER BY due", [nowSecs], kind: .learning, burySiblings: false) {
            return c
        }
        // 2. Reviews (incl. interday learning) and new cards, mixed.
        let reviewAvailable = counts.review > 0
        let newAvailable = counts.new > 0
        let review = { () -> QueuedCard? in
            if let c = first("did IN \(decks) AND queue = 3 AND due <= ? ORDER BY due, id", [timing.daysElapsed],
                             kind: .learning, burySiblings: conf.buryInterdayLearning) { return c }
            guard reviewAvailable else { return nil }
            return first("did IN \(reviewDecks) AND queue = 2 AND due <= ? ORDER BY due, (id % 1000003)",
                         [timing.daysElapsed], kind: .review, burySiblings: conf.buryReviews)
        }
        let new = { () -> QueuedCard? in
            guard newAvailable else { return nil }
            return first("did IN \(newDecks) AND queue = 0 ORDER BY due, ord", [], kind: .new, burySiblings: conf.buryNew)
        }
        let preferNew: Bool
        switch conf.newMix {
        case .beforeReviews: preferNew = true
        case .afterReviews: preferNew = false
        case .mixWithReviews:
            let ratio = counts.new > 0 ? max(1, (counts.review + counts.new) / max(counts.new, 1)) : Int.max
            preferNew = counts.review == 0 || (ratio != Int.max && answeredInSession % ratio == ratio - 1)
        }
        if preferNew, let c = new() ?? review() { return c }
        if !preferNew, let c = review() ?? new() { return c }
        // 3. Learn ahead.
        let cutoff = nowSecs + Int64(collection.learnAheadSeconds)
        return first("did IN \(decks) AND queue = 1 AND due <= ? ORDER BY due", [cutoff], kind: .learning, burySiblings: false)
    }

    public func context(for card: Card, now: Date = Date()) -> SchedulerContext {
        let timing = collection.timingToday(now: now)
        let conf = collection.deckConfig(for: card.deckId)
        let fsrs = collection.fsrsEnabled ? FSRS(params: conf.fsrsParams, desiredRetention: conf.desiredRetention) : nil
        var rng = SplitMix64(state: UInt64(bitPattern: card.id) &+ UInt64(card.reps))
        var ctx = SchedulerContext(config: conf, today: timing.daysElapsed, nowSecs: Int64(now.timeIntervalSince1970),
                                   fsrs: fsrs, fuzzFactor: rng.nextUnit())
        if fsrs != nil { ctx.elapsedDaysOverride = collection.daysSinceLastReview(card, now: now) }
        return ctx
    }

    public func nextStates(for card: Card, now: Date = Date()) -> NextStates {
        Scheduler.nextStates(for: card, context: context(for: card, now: now))
    }

    public func labels(for card: Card, now: Date = Date()) -> [Rating: String] {
        let states = nextStates(for: card, now: now)
        var out: [Rating: String] = [:]
        for r in Rating.allCases {
            out[r] = Scheduler.label(for: states.state(for: r), learnAheadSecs: collection.learnAheadSeconds)
        }
        return out
    }

    @discardableResult
    public func answer(_ card: Card, rating: Rating, millisecondsTaken: Int, now: Date = Date()) throws -> Scheduler.AnswerResult {
        let ctx = context(for: card, now: now)
        let states = Scheduler.nextStates(for: card, context: ctx)
        var rng = SplitMix64(state: UInt64(bitPattern: card.id) ^ UInt64(now.timeIntervalSince1970))
        var result = Scheduler.apply(states, rating: rating, to: card, context: ctx,
                                     answeredAtMillis: Int64(now.timeIntervalSince1970 * 1000),
                                     millisecondsTaken: millisecondsTaken, learnFuzz: rng.nextUnit())
        // Modification times must strictly increase so that sync can order changes.
        result.card.mod = max(result.card.mod, card.mod + 1)
        var noteBefore: Note?
        try collection.db.transaction {
            try collection.update(card: result.card)
            try collection.insert(revlog: result.revlog)
            if result.leeched, var note = try collection.note(id: card.noteId) {
                noteBefore = note
                if !note.tags.contains(where: { $0.lowercased() == "leech" }) {
                    note.tags.append("leech")
                    try collection.update(noteTags: note)
                }
            }
            collection.markModified()
        }
        let revlogId = (try? collection.db.scalar("SELECT max(id) FROM revlog WHERE cid = ?", [card.id]).int64) ?? result.revlog.id
        undoStack.append((card, revlogId, noteBefore, result.card.mod))
        if undoStack.count > 50 { undoStack.removeFirst() }
        seenNotes.insert(card.noteId)
        answeredInSession += 1
        refreshCounts(now: now)
        return result
    }

    /// Reverts the last answer. Returns the card so it can be shown again.
    @discardableResult
    public func undo() throws -> Card? {
        guard let last = undoStack.popLast() else { return nil }
        var restored = last.card
        // Mark the restored state as the newest change so that it also wins on other devices.
        restored.mod = max(Int64(Date().timeIntervalSince1970), last.answeredMod + 1)
        restored.usn = -1
        try collection.db.transaction {
            try collection.update(card: restored)
            try collection.db.run("DELETE FROM revlog WHERE id = ?", [last.revlogId])
            try collection.recordDeletedRevlog(last.revlogId)
            if let note = last.note { try collection.update(noteTags: note) }
        }
        answeredInSession = max(0, answeredInSession - 1)
        refreshCounts()
        return restored
    }

    public func suspend(_ card: Card) throws {
        var c = card
        c.queue = Card.Queue.suspended.rawValue
        c.mod = Int64(Date().timeIntervalSince1970)
        c.usn = -1
        try collection.update(card: c)
        refreshCounts()
    }

    public func bury(_ card: Card) throws {
        var c = card
        c.queue = Card.Queue.userBuried.rawValue
        c.mod = Int64(Date().timeIntervalSince1970)
        c.usn = -1
        try collection.update(card: c)
        refreshCounts()
    }

    public func setFlag(_ card: Card, flag: Int) throws -> Card {
        var c = card
        c.flags = (c.flags & ~0b111) | (flag & 0b111)
        c.mod = Int64(Date().timeIntervalSince1970)
        c.usn = -1
        try collection.update(card: c)
        return c
    }
}
