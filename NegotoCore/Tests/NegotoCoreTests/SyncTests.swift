import Foundation
import XCTest
@testable import NegotoCore

/// Simulates two devices sharing one iCloud Drive folder.
final class SyncTests: XCTestCase {
    var base: URL!
    var remote: URL { base.appendingPathComponent("iCloud/NegotoSync") }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func device(_ name: String) -> SyncEngine {
        let library = Library(root: base.appendingPathComponent(name))
        return SyncEngine(library: library, remoteRoot: remote, deviceID: "device-\(name)", deviceName: name)
    }

    func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    func open(_ engine: SyncEngine, _ id: UUID) throws -> AnkiCollection {
        try AnkiCollection(path: engine.library.collectionFile(for: id), mediaFolder: engine.library.mediaFolder(for: id))
    }

    func testDecksAndProgressSyncBetweenDevices() throws {
        let a = device("A"), b = device("B")
        let info = try a.library.importPackage(at: fixture("modern.apkg"))

        // A uploads the collection, B downloads it with its media.
        let r1 = try a.sync()
        XCTAssertEqual(r1.uploaded, [info.id])
        XCTAssertEqual(r1.errors, [])
        let r2 = try b.sync()
        XCTAssertEqual(r2.downloaded, [info.id])
        XCTAssertEqual(b.library.list().map(\.name), [info.name])
        let mediaA = try FileManager.default.contentsOfDirectory(atPath: a.library.mediaFolder(for: info.id).path).sorted()
        let mediaB = try FileManager.default.contentsOfDirectory(atPath: b.library.mediaFolder(for: info.id).path).sorted()
        XCTAssertEqual(mediaA, mediaB)

        // B studies a card.
        let colB = try open(b, info.id)
        let deck = try XCTUnwrap(colB.decks.values.first { $0.name == "Math & Science" })
        let sessionB = StudySession(collection: colB, deckId: deck.id)
        let q = try XCTUnwrap(sessionB.nextCard())
        let answered = try sessionB.answer(q.card, rating: .good, millisecondsTaken: 3000).card
        let reviewsB = try colB.db.scalar("SELECT count() FROM revlog").int
        colB.db.close()
        XCTAssertEqual(try b.sync().exportedCards, 1)

        // A receives B's progress.
        let r3 = try a.sync()
        XCTAssertEqual(r3.appliedCards, 1)
        XCTAssertEqual(r3.appliedReviews, 1)
        let colA = try open(a, info.id)
        let cardA = try XCTUnwrap(colA.card(id: q.card.id))
        XCTAssertEqual(cardA.queue, answered.queue)
        XCTAssertEqual(cardA.due, answered.due)
        XCTAssertEqual(cardA.reps, answered.reps)
        XCTAssertEqual(try colA.db.scalar("SELECT count() FROM revlog").int, reviewsB)

        // A studies the same card later; the newer state wins on B.
        var newer = cardA
        newer.queue = Card.Queue.suspended.rawValue
        newer.mod = cardA.mod + 10
        newer.usn = -1
        try colA.update(card: newer)
        colA.db.close()
        _ = try a.sync()
        _ = try b.sync()
        let colB2 = try open(b, info.id)
        XCTAssertEqual(try colB2.card(id: q.card.id)?.queue, Card.Queue.suspended.rawValue)

        // An older remote state never overwrites a newer local one.
        var stale = try XCTUnwrap(colB2.card(id: q.card.id))
        stale.queue = Card.Queue.review.rawValue
        stale.mod += 100
        stale.usn = 0  // pretend already synced
        try colB2.update(card: stale)
        colB2.db.close()
        _ = try b.sync()
        let colB3 = try open(b, info.id)
        XCTAssertEqual(try colB3.card(id: q.card.id)?.queue, Card.Queue.review.rawValue)
        colB3.db.close()
    }

    func testUndoIsPropagated() throws {
        let a = device("A"), b = device("B")
        let info = try a.library.importPackage(at: fixture("modern.apkg"))
        _ = try a.sync()
        _ = try b.sync()

        let colA = try open(a, info.id)
        let deck = try XCTUnwrap(colA.decks.values.first { $0.name == "Math & Science" })
        let session = StudySession(collection: colA, deckId: deck.id)
        let q = try XCTUnwrap(session.nextCard())
        try session.answer(q.card, rating: .easy, millisecondsTaken: 1000)
        let before = try colA.db.scalar("SELECT count() FROM revlog").int
        colA.db.close()
        _ = try a.sync()
        _ = try b.sync()
        XCTAssertEqual(try open(b, info.id).db.scalar("SELECT count() FROM revlog").int, before)

        let colA2 = try open(a, info.id)
        let session2 = StudySession(collection: colA2, deckId: deck.id)
        // Rebuild undo state by answering & undoing a second card, plus the undo of the first via a new answer.
        let q2 = try XCTUnwrap(session2.nextCard())
        try session2.answer(q2.card, rating: .good, millisecondsTaken: 1000)
        _ = try a.sync()
        _ = try b.sync()
        XCTAssertEqual(try open(b, info.id).db.scalar("SELECT count() FROM revlog").int, before + 1)
        try session2.undo()
        colA2.db.close()
        _ = try a.sync()
        _ = try b.sync()
        let colB = try open(b, info.id)
        XCTAssertEqual(try colB.db.scalar("SELECT count() FROM revlog").int, before)
        XCTAssertEqual(try colB.card(id: q2.card.id)?.queue, q2.card.queue)
    }

    func testRenameAndDeletionPropagate() throws {
        let a = device("A"), b = device("B")
        var info = try a.library.importPackage(at: fixture("genanki.apkg"))
        _ = try a.sync()
        _ = try b.sync()

        info.name = "名前を変更"
        info.modifiedAt = Date().addingTimeInterval(5)
        try a.library.save(info)
        _ = try a.sync()
        let r = try b.sync()
        XCTAssertEqual(r.infoUpdated, [info.id])
        XCTAssertEqual(b.library.list().first?.name, "名前を変更")

        try a.markDeleted(info.id)
        try a.library.delete(info.id)
        let r2 = try b.sync()
        XCTAssertEqual(r2.deletedRemotely, [info.id])
        // A deleted collection is not downloaded again by a third device.
        let c = device("C")
        XCTAssertEqual(try c.sync().downloaded, [])
    }

    func testIncompleteUploadIsNotDownloaded() throws {
        let a = device("A"), b = device("B")
        let info = try a.library.importPackage(at: fixture("genanki.apkg"))
        _ = try a.sync()
        try FileManager.default.removeItem(at: a.remoteDir(info.id).appendingPathComponent("info.json"))
        XCTAssertEqual(try b.sync().downloaded, [])
        XCTAssertTrue(b.library.list().isEmpty)
        // A repairs the upload on its next sync.
        let repair = try a.sync()
        XCTAssertEqual(repair.errors, [])
        XCTAssertEqual(try b.sync().downloaded, [info.id])
    }

    func testICloudPlaceholderNames() {
        XCTAssertEqual(PlainFileSystem.realName(".device-A.json.icloud"), "device-A.json")
        XCTAssertNil(PlainFileSystem.realName(".DS_Store"))
        XCTAssertEqual(PlainFileSystem.realName("a.json"), "a.json")
    }
}
