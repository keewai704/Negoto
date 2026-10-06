import Foundation
import XCTest
@testable import NegotoCore

/// Simulates several devices sharing one iCloud folder.
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

    func device(_ name: String) throws -> SyncEngine {
        let library = Library(root: base.appendingPathComponent(name))
        try library.prepare()
        library.recordsPendingOperations = true
        return SyncEngine(library: library, remoteRoot: remote, deviceID: "device-\(name)", deviceName: name)
    }

    func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    func count(_ engine: SyncEngine, _ sql: String) throws -> Int {
        let col = try engine.library.openMain()
        defer { col.db.close() }
        return try col.db.scalar(sql).int
    }

    func testDecksAndProgressSyncBetweenDevices() throws {
        let a = try device("A"), b = try device("B")
        _ = try a.library.importPackage(at: fixture("modern.apkg"))

        // A uploads the collection, B downloads it with its media.
        let r1 = try a.sync()
        XCTAssertTrue(r1.uploadedBase)
        let r2 = try b.sync()
        XCTAssertTrue(r2.downloadedBase)
        XCTAssertEqual(try count(b, "SELECT count() FROM cards"), try count(a, "SELECT count() FROM cards"))
        let mediaA = try FileManager.default.contentsOfDirectory(atPath: a.library.mainMediaFolder.path).sorted()
        let mediaB = try FileManager.default.contentsOfDirectory(atPath: b.library.mainMediaFolder.path).sorted()
        XCTAssertEqual(mediaA, mediaB)
        XCTAssertFalse(mediaA.isEmpty)

        // B studies a card.
        let colB = try b.library.openMain()
        let deck = try XCTUnwrap(colB.decks.values.first { $0.name == "Math & Science" })
        let sessionB = StudySession(collection: colB, deckId: deck.id)
        let q = try XCTUnwrap(sessionB.nextCard())
        let answered = try sessionB.answer(q.card, rating: .good, millisecondsTaken: 3000).card
        colB.db.close()
        XCTAssertEqual(try b.sync().exportedCards, 1)

        // A receives B's progress.
        let r3 = try a.sync()
        XCTAssertEqual(r3.appliedCards, 1)
        XCTAssertEqual(r3.appliedReviews, 1)
        let colA = try a.library.openMain()
        let cardA = try XCTUnwrap(colA.card(id: q.card.id))
        XCTAssertEqual(cardA.queue, answered.queue)
        XCTAssertEqual(cardA.due, answered.due)

        // A's later change wins on B.
        var newer = cardA
        newer.queue = Card.Queue.suspended.rawValue
        newer.mod = cardA.mod + 10
        newer.usn = -1
        try colA.update(card: newer)
        colA.db.close()
        _ = try a.sync()
        _ = try b.sync()
        let colB2 = try b.library.openMain()
        XCTAssertEqual(try colB2.card(id: q.card.id)?.queue, Card.Queue.suspended.rawValue)
        colB2.db.close()
    }

    func testImportOnSecondDeviceIsShared() throws {
        let a = try device("A"), b = try device("B")
        _ = try a.library.importPackage(at: fixture("modern.apkg"))
        _ = try a.sync()
        _ = try b.sync()
        // B imports another deck → new base; A gets it without losing its progress.
        let colA = try a.library.openMain()
        let deck = try XCTUnwrap(colA.decks.values.first { $0.name == "Math & Science" })
        let s = StudySession(collection: colA, deckId: deck.id)
        let q = try XCTUnwrap(s.nextCard())
        try s.answer(q.card, rating: .easy, millisecondsTaken: 1000)
        colA.db.close()

        _ = try b.library.importPackage(at: fixture("genanki.apkg"))
        XCTAssertTrue(try b.sync().uploadedBase)
        _ = try a.sync()  // A: exports its answer, downloads B's base, re-applies its own answer
        XCTAssertTrue(try a.library.openMain().decks.values.contains { $0.name == "Genanki::Old Deck" })
        XCTAssertEqual(try a.library.openMain().card(id: q.card.id)?.type, Card.CardType.review.rawValue)
        _ = try b.sync()
        XCTAssertEqual(try b.library.openMain().card(id: q.card.id)?.type, Card.CardType.review.rawValue)
        XCTAssertEqual(try count(a, "SELECT count() FROM notes"), try count(b, "SELECT count() FROM notes"))
    }

    func testConcurrentImportsAreBothKept() throws {
        let a = try device("A"), b = try device("B")
        _ = try a.library.importPackage(at: fixture("modern.apkg"))
        _ = try a.sync()
        _ = try b.sync()
        // Both import while offline; B syncs second and must replay its import on A's new base.
        _ = try a.library.importPackage(at: fixture("genanki.apkg"))
        _ = try b.library.importPackage(at: fixture("fsrs.apkg"))
        _ = try a.sync()
        _ = try b.sync()
        _ = try a.sync()
        let notesA = try count(a, "SELECT count() FROM notes")
        XCTAssertEqual(notesA, try count(b, "SELECT count() FROM notes"))
        XCTAssertEqual(notesA, 12 + 2 + 10)
    }

    func testJoiningWithOwnDecksMergesThem() throws {
        let a = try device("A"), b = try device("B")
        _ = try a.library.importPackage(at: fixture("modern.apkg"))
        _ = try a.sync()
        // B already has decks (imported before turning sync on), including the same deck as A.
        b.library.recordsPendingOperations = false
        _ = try b.library.importPackage(at: fixture("modern.apkg"))
        _ = try b.library.importPackage(at: fixture("genanki.apkg"))
        XCTAssertTrue(try b.sync().uploadedBase)
        _ = try a.sync()
        XCTAssertEqual(try count(a, "SELECT count() FROM notes"), 12 + 2)  // no duplicates
        XCTAssertEqual(try count(b, "SELECT count() FROM notes"), 12 + 2)
    }

    func testDeckOptionsAndRenameSync() throws {
        let a = try device("A"), b = try device("B")
        _ = try a.library.importPackage(at: fixture("modern.apkg"))
        _ = try a.sync()
        _ = try b.sync()
        let colA = try a.library.openMain()
        let deck = try XCTUnwrap(colA.decks.values.first { $0.name == "Math & Science" })
        var conf = colA.deckConfig(for: deck.id)
        conf.newPerDay = 7
        conf.learnSteps = [2, 20, 60]
        try colA.save(deckConfig: conf)
        try colA.setDeckLimits(deck: deck.id, newLimit: 3, reviewLimit: nil)
        try colA.renameDeck(deck.id, to: "数学")
        try colA.setFSRS(true)
        colA.db.close()
        _ = try a.sync()
        XCTAssertGreaterThan(try b.sync().appliedSettings, 0)
        let colB = try b.library.openMain()
        let deckB = try XCTUnwrap(colB.decks[deck.id])
        XCTAssertEqual(deckB.name, "数学")
        XCTAssertEqual(deckB.newLimit, 3)
        XCTAssertEqual(colB.deckConfig(for: deck.id).newPerDay, 7)
        XCTAssertEqual(colB.deckConfig(for: deck.id).learnSteps, [2, 20, 60])
        XCTAssertTrue(colB.fsrsEnabled)
    }

    func testUndoAndDeckDeletionPropagate() throws {
        let a = try device("A"), b = try device("B")
        _ = try a.library.importPackage(at: fixture("modern.apkg"))
        _ = try a.sync()
        _ = try b.sync()
        let before = try count(b, "SELECT count() FROM revlog")

        let colA = try a.library.openMain()
        let deck = try XCTUnwrap(colA.decks.values.first { $0.name == "Math & Science" })
        let session = StudySession(collection: colA, deckId: deck.id)
        let q = try XCTUnwrap(session.nextCard())
        try session.answer(q.card, rating: .good, millisecondsTaken: 1000)
        _ = try a.sync()
        _ = try b.sync()
        XCTAssertEqual(try count(b, "SELECT count() FROM revlog"), before + 1)
        try session.undo()
        _ = try a.sync()
        _ = try b.sync()
        XCTAssertEqual(try count(b, "SELECT count() FROM revlog"), before)
        XCTAssertEqual(try b.library.openMain().card(id: q.card.id)?.queue, q.card.queue)

        let occlusion = try XCTUnwrap(colA.decks.values.first { $0.name == "Occlusion" })
        try a.library.deleteDeck(occlusion.id, in: colA)
        colA.db.close()
        XCTAssertTrue(try a.sync().uploadedBase)
        _ = try b.sync()
        XCTAssertFalse(try b.library.openMain().decks.values.contains { $0.name == "Occlusion" })
    }

    func testICloudPlaceholderNames() {
        XCTAssertEqual(PlainFileSystem.realName(".device-A.json.icloud"), "device-A.json")
        XCTAssertNil(PlainFileSystem.realName(".DS_Store"))
        XCTAssertEqual(PlainFileSystem.realName("a.json"), "a.json")
    }
}

final class SingleCollectionTests: XCTestCase {
    func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    func makeLibrary() throws -> Library {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-lib-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let lib = Library(root: root)
        try lib.prepare()
        return lib
    }

    func testImportsMergeIntoOneCollection() throws {
        let lib = try makeLibrary()
        let r1 = try lib.importPackage(at: fixture("modern.apkg"))
        XCTAssertEqual(r1.merge.addedNotes, 12)
        XCTAssertEqual(r1.merge.addedCards, 19)
        let r2 = try lib.importPackage(at: fixture("legacy.apkg"))  // same notes again
        XCTAssertEqual(r2.merge.addedNotes, 0)
        XCTAssertEqual(r2.merge.skippedNotes, 12)
        _ = try lib.importPackage(at: fixture("genanki.apkg"))
        let col = try lib.openMain()
        XCTAssertEqual(col.noteCount, 14)
        XCTAssertFalse(col.usesSeparateTables)
        XCTAssertTrue(col.decks.values.contains { $0.name == "日本語::語彙" })
        XCTAssertTrue(col.decks.values.contains { $0.name == "Genanki" })
        // Imported cards render the same as in Anki (spot check: cloze with hint).
        let cid = try col.db.scalar("SELECT c.id FROM cards c JOIN notes n ON n.id = c.nid WHERE n.flds LIKE '%Canberra%' AND c.ord = 0").int64
        let card = try XCTUnwrap(col.card(id: cid))
        let note = try XCTUnwrap(col.note(id: card.noteId))
        let r = CardRenderer.render(card: card, note: note, notetype: col.notetypes[note.notetypeId]!, deckName: col.deckName(card.deckId))
        XCTAssertTrue(r.question.contains("[city]"))
        // Scheduling carried over: review cards stay due relative to today.
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM cards WHERE type = 2").int, 4)
    }

    func testReplaceMode() throws {
        let lib = try makeLibrary()
        _ = try lib.importPackage(at: fixture("genanki.apkg"))
        _ = try lib.importPackage(at: fixture("modern.colpkg"), mode: .replace)
        let col = try lib.openMain()
        XCTAssertEqual(col.noteCount, 12)
        XCTAssertFalse(col.decks.values.contains { $0.name.hasPrefix("Genanki") })
    }

    func testMediaNameClashIsRenamed() throws {
        let lib = try makeLibrary()
        _ = try lib.importPackage(at: fixture("modern.apkg"))
        // Same file name, different content.
        try Data("other".utf8).write(to: lib.mainMediaFolder.appendingPathComponent("tokyo.png"))
        let r = try lib.importPackage(at: fixture("genanki.apkg"))
        XCTAssertEqual(r.merge.renamedMedia, 1)
        let col = try lib.openMain()
        let flds = try col.db.scalar("SELECT flds FROM notes WHERE flds LIKE '%Tokyo%'").string
        XCTAssertFalse(flds.contains("\"tokyo.png\""))
        XCTAssertTrue(flds.contains("tokyo-"))
    }

    func testLegacyCollectionsAreMigrated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-mig-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        // Layout of Negoto ≤1.0.6: one folder per imported package.
        for pkg in ["modern.apkg", "genanki.apkg"] {
            _ = try PackageImporter.importPackage(at: fixture(pkg), into: root.appendingPathComponent("collections/\(UUID().uuidString)"))
        }
        let lib = Library(root: root)
        try lib.prepare()
        let dirs = try FileManager.default.contentsOfDirectory(atPath: lib.collectionsDir.path)
        XCTAssertEqual(dirs, [Library.mainID.uuidString])
        XCTAssertEqual(try lib.openMain().noteCount, 14)
    }

    func testDeckEditing() throws {
        let lib = try makeLibrary()
        _ = try lib.importPackage(at: fixture("modern.apkg"))
        let col = try lib.openMain()
        let parent = try XCTUnwrap(col.decks.values.first { $0.name == "日本語" })
        try col.renameDeck(parent.id, to: "Japanese")
        XCTAssertTrue(col.decks.values.contains { $0.name == "Japanese::語彙" })
        let child = try XCTUnwrap(col.decks.values.first { $0.name == "Japanese::語彙" })
        let preset = try col.addDeckConfig(copying: col.deckConfig(for: child.id), name: "語彙専用")
        try col.setDeckConfigID(deck: child.id, configID: preset.id)
        XCTAssertEqual(col.deckConfig(for: child.id).name, "語彙専用")
        // Studying the parent includes the subdeck.
        XCTAssertEqual(col.counts(for: parent.id).total, col.counts(for: child.id).total)
        XCTAssertGreaterThan(col.counts(for: parent.id).total, 0)
        try lib.deleteDeck(parent.id, in: col)
        XCTAssertFalse(col.decks.values.contains { $0.name.hasPrefix("Japanese") })
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM cards WHERE did = ?", [child.id]).int, 0)
    }
}
