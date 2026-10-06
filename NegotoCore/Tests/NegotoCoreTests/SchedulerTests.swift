import Foundation
import XCTest
@testable import NegotoCore

final class SchedulerTests: XCTestCase {
    struct Expected: Decodable {
        struct CardInfo: Decodable {
            var next_labels: [String]
            var type: Int
        }
        var now: Int64
        var learn_ahead_secs: Int
        var cards: [String: CardInfo]
    }

    static func load(_ json: String) throws -> Expected {
        let url = Bundle.module.url(forResource: json, withExtension: nil, subdirectory: "Fixtures")!
        return try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url))
    }

    static func openCollection(_ package: String) throws -> AnkiCollection {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-sched-\(UUID().uuidString)")
        let src = Bundle.module.url(forResource: package, withExtension: nil, subdirectory: "Fixtures")!
        let summary = try PackageImporter.importPackage(at: src, into: dest)
        return try AnkiCollection(path: summary.collectionFile, mediaFolder: summary.mediaFolder)
    }

    /// Parses Anki's answer-button label ("<⁨10⁩m", "⁨1.4⁩mo") into seconds.
    static func seconds(_ label: String) -> (secs: Double, lessThan: Bool) {
        var s = label.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
        let lessThan = s.hasPrefix("<")
        if lessThan { s.removeFirst() }
        let units: [(String, Double)] = [("mo", 2_592_000), ("s", 1), ("m", 60), ("h", 3600), ("d", 86_400), ("y", 31_536_000)]
        for (u, mult) in units where s.hasSuffix(u) {
            if let v = Double(s.dropLast(u.count)) { return (v * mult, lessThan) }
        }
        return (-1, lessThan)
    }

    func checkLabels(package: String, expectedJSON: String) throws {
        let exp = try Self.load(expectedJSON)
        let col = try Self.openCollection(package)
        let now = Date(timeIntervalSince1970: TimeInterval(exp.now))
        let timing = col.timingToday(now: now, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(timing.daysElapsed, 0)
        for (cidString, info) in exp.cards {
            let card = try XCTUnwrap(col.card(id: Int64(cidString)!))
            let conf = col.deckConfig(for: card.deckId)
            let fsrs = col.fsrsEnabled ? FSRS(params: conf.fsrsParams, desiredRetention: conf.desiredRetention) : nil
            let ctx = SchedulerContext(config: conf, today: timing.daysElapsed, nowSecs: exp.now, fsrs: fsrs, fuzzFactor: nil)
            let states = Scheduler.nextStates(for: card, context: ctx)
            for (i, rating) in Rating.allCases.enumerated() {
                let state = states.state(for: rating)
                let ours = Scheduler.label(for: state, learnAheadSecs: exp.learn_ahead_secs)
                let anki = Self.seconds(info.next_labels[i])
                if case .review(let r) = state {
                    // Anki fuzzes review intervals; ours (unfuzzed) must allow Anki's value.
                    let (lo, hi) = SchedulerContext.fuzzBounds(Double(r.scheduledDays), minimum: 1, maximum: conf.maximumReviewInterval)
                    let ankiDays = anki.secs / 86_400
                    // Anki chains fuzzed minimums (easy ≥ fuzzed good + 1), so allow a little slack.
                    let tolerance = max(2.5, ankiDays * 0.06)
                    XCTAssert(ankiDays >= Double(min(lo, r.scheduledDays)) - tolerance && ankiDays <= Double(max(hi, r.scheduledDays)) + tolerance,
                              "\(package) card \(cidString) \(rating): anki \(info.next_labels[i]) vs ours \(r.scheduledDays)d [\(lo),\(hi)]")
                } else {
                    XCTAssertEqual(ours, info.next_labels[i].replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: ""),
                                   "\(package) card \(cidString) \(rating)")
                }
            }
        }
    }

    func testSM2LabelsMatchAnki() throws {
        try checkLabels(package: "modern.apkg", expectedJSON: "expected.json")
        try checkLabels(package: "legacy.apkg", expectedJSON: "expected.json")
    }

    func testFuzzBounds() {
        func b(_ i: Double, _ mx: Int) -> [Int] { let r = SchedulerContext.fuzzBounds(i, minimum: 1, maximum: mx); return [r.0, r.1] }
        XCTAssertEqual(b(1, 100), [1, 1])
        XCTAssertEqual(b(10, 100), [8, 12])
        XCTAssertEqual(b(100, 36500), [93, 107])
    }

    func testFormatInterval() {
        XCTAssertEqual(Scheduler.formatInterval(60), "1m")
        XCTAssertEqual(Scheduler.formatInterval(330), "6m")
        XCTAssertEqual(Scheduler.formatInterval(86_400 * 21), "21d")
        XCTAssertEqual(Scheduler.formatInterval(86_400 * 42), "1.4mo")
        XCTAssertEqual(Scheduler.formatInterval(3600 * 5), "5h")
    }

    func testStudySessionAnswersAndUndo() throws {
        let col = try Self.openCollection("modern.apkg")
        let deck = try XCTUnwrap(col.decks.values.first { $0.name == "Math & Science" })
        let session = StudySession(collection: col, deckId: deck.id)
        let before = session.counts
        XCTAssertGreaterThan(before.total, 0)
        let q = try XCTUnwrap(session.nextCard())
        let revlogBefore = try col.db.scalar("SELECT count() FROM revlog").int
        let result = try session.answer(q.card, rating: .good, millisecondsTaken: 4000)
        XCTAssertEqual(result.card.reps, q.card.reps + 1)
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM revlog").int, revlogBefore + 1)
        let stored = try XCTUnwrap(col.card(id: q.card.id))
        XCTAssertEqual(stored.queue, result.card.queue)
        XCTAssertTrue(session.canUndo)
        try session.undo()
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM revlog").int, revlogBefore)
        var restored = try XCTUnwrap(col.card(id: q.card.id))
        XCTAssertEqual(restored.usn, -1)  // marked as a change so the undo syncs
        restored.mod = q.card.mod
        restored.usn = q.card.usn
        XCTAssertEqual(restored, q.card)
    }

    func testLearningSequenceGraduates() throws {
        var conf = DeckConfig(id: 1, name: "t")
        conf.learnSteps = [1, 10]
        conf.graduatingIntervalGood = 1
        conf.graduatingIntervalEasy = 4
        var card = Card(id: 1, noteId: 1, deckId: 1, ord: 0, mod: 0, usn: 0, type: 0, queue: 0, due: 1, interval: 0,
                        factor: 0, reps: 0, lapses: 0, left: 0, originalDue: 0, originalDeckId: 0, flags: 0, data: "")
        let ctx = SchedulerContext(config: conf, today: 10, nowSecs: 1_000_000_000)
        // Steps [1m, 10m]: new → step 2 (10m) → graduate.
        for expected in [Card.Queue.learning, .review] {
            let states = Scheduler.nextStates(for: card, context: ctx)
            card = Scheduler.apply(states, rating: .good, to: card, context: ctx, answeredAtMillis: 0, millisecondsTaken: 1).card
            XCTAssertEqual(card.queue, expected.rawValue)
        }
        XCTAssertEqual(card.interval, 1)
        XCTAssertEqual(card.due, 11)
        XCTAssertEqual(card.factor, 2500)
        // Lapse with relearning step
        let lapseCtx = SchedulerContext(config: conf, today: 11, nowSecs: 1_000_100_000)
        let lapse = Scheduler.apply(Scheduler.nextStates(for: card, context: lapseCtx), rating: .again, to: card,
                                    context: lapseCtx, answeredAtMillis: 0, millisecondsTaken: 1)
        XCTAssertEqual(lapse.card.type, Card.CardType.relearning.rawValue)
        XCTAssertEqual(lapse.card.lapses, 1)
        XCTAssertEqual(lapse.card.factor, 2300)
        XCTAssertEqual(lapse.revlog.type, 1)
    }

    func testLeechThreshold() {
        XCTAssertFalse(Scheduler.leechThresholdMet(lapses: 7, threshold: 8))
        XCTAssertTrue(Scheduler.leechThresholdMet(lapses: 8, threshold: 8))
        XCTAssertFalse(Scheduler.leechThresholdMet(lapses: 9, threshold: 8))
        XCTAssertTrue(Scheduler.leechThresholdMet(lapses: 12, threshold: 8))
    }
}

final class FSRSTests: XCTestCase {
    struct Expected: Decodable {
        struct CardInfo: Decodable {
            var next_labels: [String]
            var type: Int
            var stability: Double?
            var difficulty: Double?
        }
        var now: Int64
        var learn_ahead_secs: Int
        var cards: [String: CardInfo]
    }

    func testFSRSMatchesAnki() throws {
        let url = Bundle.module.url(forResource: "expected_fsrs.json", withExtension: nil, subdirectory: "Fixtures")!
        let exp = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url))
        let col = try SchedulerTests.openCollection("fsrs.apkg")
        // An .apkg doesn't include the collection-wide FSRS switch; the app decides.
        XCTAssertFalse(col.fsrsEnabled)
        col.fsrsOverride = true
        XCTAssertTrue(col.fsrsEnabled)
        let now = Date(timeIntervalSince1970: TimeInterval(exp.now))
        for (cidString, info) in exp.cards {
            let card = try XCTUnwrap(col.card(id: Int64(cidString)!))
            if let s = info.stability, let d = info.difficulty {
                let m = try XCTUnwrap(card.memoryState)
                XCTAssertEqual(m.stability, s, accuracy: 0.01)
                XCTAssertEqual(m.difficulty, d, accuracy: 0.01)
            }
            let conf = col.deckConfig(for: card.deckId)
            XCTAssertEqual(conf.fsrsParams.count, 21)
            var ctx = SchedulerContext(config: conf, today: 0, nowSecs: exp.now,
                                       fsrs: FSRS(params: conf.fsrsParams, desiredRetention: conf.desiredRetention), fuzzFactor: nil)
            ctx.elapsedDaysOverride = col.daysSinceLastReview(card, now: now)
            let states = Scheduler.nextStates(for: card, context: ctx)
            for (i, rating) in Rating.allCases.enumerated() {
                let state = states.state(for: rating)
                let anki = SchedulerTests.seconds(info.next_labels[i])
                if case .review(let r) = state {
                    let ankiDays = anki.secs / 86_400
                    let (lo, hi) = SchedulerContext.fuzzBounds(Double(r.scheduledDays), minimum: 1, maximum: 36500)
                    XCTAssert(ankiDays >= Double(lo) - max(2.5, ankiDays * 0.06) && ankiDays <= Double(hi) + max(2.5, ankiDays * 0.06),
                              "card \(cidString) \(rating): anki \(info.next_labels[i]) vs ours \(r.scheduledDays)d")
                } else {
                    let ours = Scheduler.label(for: state, learnAheadSecs: exp.learn_ahead_secs)
                    XCTAssertEqual(ours, info.next_labels[i].replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: ""),
                                   "card \(cidString) \(rating)")
                }
            }
        }
    }

    func testFSRSFormulas() throws {
        let f = try XCTUnwrap(FSRS(params: FSRS.defaultParams6, desiredRetention: 0.9))
        // Values verified against Anki 26.9 (see scripts/fixtures).
        let m = MemoryState(stability: 10, difficulty: 5)
        let late = f.next(m, elapsedDays: 10)
        XCTAssertEqual(late.hard.stability, 23.247, accuracy: 0.01)
        XCTAssertEqual(late.good.stability, 32.027, accuracy: 0.01)
        XCTAssertEqual(late.easy.stability, 51.254, accuracy: 0.01)
        XCTAssertEqual(late.again.stability, 1.392, accuracy: 0.01)
        XCTAssertEqual(late.hard.difficulty, 6.666, accuracy: 0.01)
        let same = f.next(m, elapsedDays: 0)
        XCTAssertEqual(same.again.stability, 3.051, accuracy: 0.01)
        XCTAssertEqual(same.hard.stability, 10.0, accuracy: 0.01)
        XCTAssertEqual(same.easy.stability, 15.534, accuracy: 0.01)
    }
}
