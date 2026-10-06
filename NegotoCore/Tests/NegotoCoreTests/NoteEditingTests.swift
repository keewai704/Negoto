import Foundation
import XCTest
@testable import NegotoCore

final class NoteEditingTests: XCTestCase {
    var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    func library(_ name: String = "lib") throws -> Library {
        let lib = Library(root: base.appendingPathComponent(name))
        try lib.prepare()
        _ = try lib.importPackage(at: fixture("modern.apkg"))
        return lib
    }

    func notetype(_ col: AnkiCollection, _ name: String) throws -> Notetype {
        try XCTUnwrap(col.notetypes.values.first { $0.name == name })
    }

    /// The card-generation rule agrees with the cards Anki created for every fixture note.
    func testCardOrdinalsMatchAnki() throws {
        let col = try library().openMain()
        defer { col.db.close() }
        var checked = 0
        for row in try col.db.query("SELECT id FROM notes") {
            let note = try XCTUnwrap(col.note(id: row[0].int64))
            let nt = try XCTUnwrap(col.notetypes[note.notetypeId])
            if nt.name.contains("Occlusion") { continue }
            let anki = try col.db.query("SELECT ord FROM cards WHERE nid = ? ORDER BY ord", [note.id]).map { $0[0].int }
            XCTAssertEqual(col.cardOrdinals(notetype: nt, fields: note.fields), anki, "\(nt.name): \(note.fields)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 5)
    }

    func testAddEditAndDeleteNotes() throws {
        let col = try library().openMain()
        defer { col.db.close() }
        let basic = try notetype(col, "Basic (and reversed card)")
        let deck = try col.findOrCreateDeck(named: "英単語::TOEIC")
        let before = col.counts(for: deck)

        let id = try col.addNote(notetypeId: basic.id, deckId: deck, fields: ["ubiquitous", "どこにでもある"], tags: ["形容詞", "頻出"])
        let note = try XCTUnwrap(col.note(id: id))
        XCTAssertEqual(note.fields, ["ubiquitous", "どこにでもある"])
        XCTAssertEqual(Set(note.tags), ["形容詞", "頻出"])
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM cards WHERE nid = ?", [id]).int, 2)
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM notes WHERE id = ? AND usn = -1 AND sfld = 'ubiquitous'", [id]).int, 1)
        XCTAssertEqual(col.counts(for: deck).new, before.new + 2)
        // New cards are studied after the existing ones.
        let maxOld = try col.db.scalar("SELECT max(due) FROM cards WHERE type = 0 AND nid != ?", [id]).int64
        XCTAssertGreaterThan(try col.db.scalar("SELECT min(due) FROM cards WHERE nid = ?", [id]).int64, maxOld)

        XCTAssertThrowsError(try col.addNote(notetypeId: basic.id, deckId: deck, fields: ["", "<br>"], tags: [])) {
            XCTAssertEqual($0 as? NoteEditError, .noCards)
        }

        let cloze = try notetype(col, "Cloze")
        let cid = try col.addNote(notetypeId: cloze.id, deckId: deck, fields: ["{{c1::東京}}は{{c2::日本}}の首都", ""], tags: [])
        XCTAssertEqual(try col.db.query("SELECT ord FROM cards WHERE nid = ? ORDER BY ord", [cid]).map { $0[0].int }, [0, 1])
        XCTAssertEqual(try col.updateNote(id: cid, fields: ["{{c1::東京}}は{{c2::日本}}の{{c3::首都}}", ""], tags: ["地理"]), 1)
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM cards WHERE nid = ?", [cid]).int, 3)
        XCTAssertEqual(try col.note(id: cid)?.tags, ["地理"])
        XCTAssertThrowsError(try col.addNote(notetypeId: cloze.id, deckId: deck, fields: ["no clozes", ""], tags: []))

        XCTAssertEqual(col.countCards("tag:地理"), 3)
        try col.deleteNotes([cid])
        XCTAssertEqual(col.countCards("tag:地理"), 0)
        XCTAssertEqual(try col.db.scalar("SELECT count() FROM negoto_deleted_notes").int, 1)
        XCTAssertTrue(col.allTags().contains("頻出"))
    }

    func testSearch() throws {
        let col = try library().openMain()
        defer { col.db.close() }
        let total = col.cardCount
        XCTAssertEqual(col.countCards(""), total)
        XCTAssertEqual(col.countCards("deck:日本語"), col.countCards("deck:日本語::語彙"))
        XCTAssertGreaterThan(col.countCards("deck:日本語"), 0)
        XCTAssertEqual(col.countCards("deck:日本語") + col.countCards("-deck:日本語"), total)
        XCTAssertEqual(col.countCards("deck:\"Math & Science\""), col.totalCards(in: try XCTUnwrap(col.decks.values.first { $0.name == "Math & Science" }).id))
        XCTAssertEqual(col.countCards("deck:Math*"), col.countCards("deck:\"Math & Science\""))
        XCTAssertEqual(col.countCards("tag:jp"), 1)  // child tag jp::n5
        XCTAssertEqual(col.countCards("tag:animal"), 1)
        XCTAssertEqual(col.countCards("Canberra"), 3)
        XCTAssertEqual(col.countCards("is:new"), col.countCards("-is:review -is:learn"))
        XCTAssertEqual(col.countCards("note:Cloze"), col.countCards("note:cloze"))
        XCTAssertEqual(col.countCards("front:Hund*"), 2)
        XCTAssertEqual(col.countCards("tag:animal or Canberra"), 4)
        XCTAssertEqual(col.countCards("is:suspended"), 0)
        XCTAssertEqual(col.countCards("prop:ivl>=1"), col.countCards("is:review"))
    }

    func testCustomStudyExtendsTodayLimits() throws {
        let col = try library().openMain()
        defer { col.db.close() }
        let deck = try XCTUnwrap(col.decks.values.first { $0.name == "Math & Science" })
        var conf = col.deckConfig(for: deck.id)
        conf.newPerDay = 1
        try col.save(deckConfig: conf)
        XCTAssertEqual(col.counts(for: deck.id).new, 1)
        try col.extendTodayLimits(deck: deck.id, new: 2, review: 0)
        XCTAssertEqual(col.counts(for: deck.id).new, 3)
        try col.extendTodayLimits(deck: deck.id, new: 1, review: 0)
        XCTAssertEqual(col.decks[deck.id]?.extendNew, 3)
    }

    func testAddedNotesSyncToOtherDevices() throws {
        let remote = base.appendingPathComponent("iCloud")
        func engine(_ name: String, _ lib: Library) -> SyncEngine {
            lib.recordsPendingOperations = true
            return SyncEngine(library: lib, remoteRoot: remote, deviceID: name, deviceName: name)
        }
        let libA = try library("A")
        let libB = Library(root: base.appendingPathComponent("B"))
        try libB.prepare()
        let a = engine("A", libA), b = engine("B", libB)
        _ = try a.sync()
        _ = try b.sync()

        // A creates a deck and a note, edits an existing note and deletes another.
        var colA = try libA.openMain()
        let basic = try notetype(colA, "Basic")
        let deck = try colA.findOrCreateDeck(named: "新しいデッキ")
        let added = try colA.addNote(notetypeId: basic.id, deckId: deck, fields: ["新しい", "カード"], tags: ["new"])
        let edited = try colA.db.scalar("SELECT id FROM notes WHERE flds LIKE 'Empty back%'").int64
        try colA.updateNote(id: edited, fields: ["Edited front", "now with back"], tags: [])
        let removed = try colA.db.scalar("SELECT id FROM notes WHERE flds LIKE 'Hund%'").int64
        try colA.deleteNotes([removed])
        colA.db.close()
        _ = try a.sync()
        _ = try b.sync()

        var colB = try libB.openMain()
        XCTAssertEqual(try colB.note(id: added)?.fields, ["新しい", "カード"])
        XCTAssertEqual(try colB.db.scalar("SELECT count() FROM cards WHERE nid = ?", [added]).int, 1)
        XCTAssertEqual(try colB.db.scalar("SELECT d FROM (SELECT did AS d FROM cards WHERE nid = ?)", [added]).int64, deck)
        XCTAssertEqual(colB.decks[deck]?.name, "新しいデッキ")
        XCTAssertEqual(try colB.note(id: edited)?.fields, ["Edited front", "now with back"])
        XCTAssertNil(try colB.note(id: removed))
        XCTAssertEqual(try colB.db.scalar("SELECT count() FROM cards WHERE nid = ?", [removed]).int, 0)

        // B studies the new card; A gets the progress.
        let session = StudySession(collection: colB, deckId: deck)
        let q = try XCTUnwrap(session.nextCard())
        XCTAssertEqual(q.card.noteId, added)
        _ = try session.answer(q.card, rating: .good, millisecondsTaken: 1000)
        colB.db.close()
        _ = try b.sync()
        _ = try a.sync()
        colA = try libA.openMain()
        XCTAssertEqual(try colA.card(id: q.card.id)?.reps, 1)
        colA.db.close()

        // A third device that joins later gets everything from the base and the change files.
        let libC = Library(root: base.appendingPathComponent("C"))
        try libC.prepare()
        _ = try engine("C", libC).sync()
        colB = try libC.openMain()
        XCTAssertEqual(try colB.note(id: added)?.fields, ["新しい", "カード"])
        XCTAssertNil(try colB.note(id: removed))
        colB.db.close()
    }
}
