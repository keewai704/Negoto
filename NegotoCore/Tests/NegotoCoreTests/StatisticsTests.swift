import Foundation
import XCTest
@testable import NegotoCore

final class StatisticsTests: XCTestCase {
    struct Expected: Decodable { var now: Int64 }

    func testStatisticsOfFixture() throws {
        let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        let exp = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: fixtures.appendingPathComponent("expected.json")))
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-stats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }
        let summary = try PackageImporter.importPackage(at: fixtures.appendingPathComponent("modern.apkg"), into: dest)
        let col = try AnkiCollection(path: summary.collectionFile, mediaFolder: summary.mediaFolder)
        let now = Date(timeIntervalSince1970: TimeInterval(exp.now))
        let stats = CollectionStatistics(collection: col, now: now)

        // The generator answered 8 cards with 13 button presses in total, all "today".
        let today = stats.todayStats()
        XCTAssertEqual(today.reviews, 13)
        XCTAssertEqual(today.again, 2)
        XCTAssertEqual(today.newCards, 8)
        XCTAssertEqual(stats.daily(days: 7).count, 7)
        XCTAssertEqual(stats.daily(days: 7).last?.total, 13)
        XCTAssertEqual(stats.streak().current, 1)
        XCTAssertEqual(stats.heatmap(days: 30)[0], 13)

        let states = stats.cardStates()
        XCTAssertEqual(states.total, 19)
        XCTAssertEqual(states.new, 11)
        XCTAssertEqual(states.young + states.mature, 4)
        XCTAssertEqual(stats.forecast(days: 30).reduce(0) { $0 + $1.total }, 8)
        XCTAssertEqual(stats.intervalBuckets().reduce(0) { $0 + $1.count }, 4)
        let buttons = stats.answerButtons(days: 30)
        XCTAssertEqual(buttons.values.reduce(0) { $0 + $1.total }, 13)
        XCTAssertEqual(stats.hourly(days: 30).reduce(0) { $0 + $1.count }, 13)

        // Restricted to one deck.
        let deck = try XCTUnwrap(col.decks.values.first { $0.name == "Occlusion" })
        let deckStats = CollectionStatistics(collection: col, deckID: deck.id, now: now)
        XCTAssertEqual(deckStats.cardStates().total, 3)
        XCTAssertEqual(deckStats.todayStats().reviews, 0)

        // Counts for "all decks" equal the sum of top-level decks.
        let all = col.counts(for: AnkiCollection.allDecksID, now: now)
        let sum = col.rootDecks.map { col.counts(for: $0.id, now: now) }.reduce(0) { $0 + $1.total }
        XCTAssertEqual(all.total, sum)
        let session = StudySession(collection: col, deckId: AnkiCollection.allDecksID)
        XCTAssertNotNil(session.nextCard(now: now))
    }
}
