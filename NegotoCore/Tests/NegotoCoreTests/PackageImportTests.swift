import Foundation
import XCTest
@testable import NegotoCore

/// Imports packages produced by the official Anki library (see scripts/fixtures) and checks that
/// Negoto renders every card exactly like Anki's own renderer.
final class PackageImportTests: XCTestCase {
    struct Expected: Decodable {
        struct CardInfo: Decodable {
            var nid: Int64
            var ord: Int
            var did: Int64
            var question: String
            var answer: String
            var question_av: [[String: AnyCodable]]
            var answer_av: [[String: AnyCodable]]
            var type: Int
            var queue: Int
            var due: Int64
            var ivl: Int
            var factor: Int
            var left: Int
            var next_labels: [String]
        }
        var cards: [String: CardInfo]
        var decks: [String]
        var note_count: Int
        var card_count: Int
        var media: [String]
    }

    struct AnyCodable: Decodable {
        var value: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { value = s } else if let d = try? c.decode(Double.self) { value = d } else if let a = try? c.decode([String].self) { value = a } else { value = "" }
        }
    }

    static func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    static let expected: Expected = {
        let data = try! Data(contentsOf: fixture("expected.json"))
        return try! JSONDecoder().decode(Expected.self, from: data)
    }()

    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Hint ids are hashes whose exact value is irrelevant.
    static func normalizeHintIds(_ s: String) -> String {
        HTMLText.replace(try! NSRegularExpression(pattern: "hint[0-9a-f]{6,}"), in: s, with: "hintID")
    }

    /// Anki appends a notice when it can't generate LaTeX images; that's not part of the card.
    static func dropLatexNotice(_ s: String) -> String {
        s.replacingOccurrences(of: "<br>\nLaTeX image generation is disabled in the preferences.", with: "<br>\n")
            .replacingOccurrences(of: "LaTeX image generation is disabled in the preferences.", with: "")
    }

    func checkPackage(_ name: String, expectedFormat: PackageFormat) throws {
        let dest = tempDir()
        let summary = try PackageImporter.importPackage(at: Self.fixture(name), into: dest)
        XCTAssertEqual(summary.format, expectedFormat, name)
        let exp = Self.expected
        XCTAssertEqual(summary.noteCount, exp.note_count, name)
        XCTAssertEqual(summary.cardCount, exp.card_count, name)
        XCTAssertEqual(summary.missingMedia, [], name)
        let mediaFiles = try FileManager.default.contentsOfDirectory(atPath: summary.mediaFolder.path).sorted()
        XCTAssertEqual(mediaFiles.map { $0.precomposedStringWithCanonicalMapping }, exp.media.sorted(), name)
        // Media content must be decompressed.
        let png = try Data(contentsOf: summary.mediaFolder.appendingPathComponent("io-image.png"))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], name)

        let col = try AnkiCollection(path: summary.collectionFile, mediaFolder: summary.mediaFolder)
        let deckNames = col.decks.values.map(\.name).sorted()
        XCTAssertEqual(deckNames, exp.decks.sorted(), name)
        XCTAssertEqual(col.notetypes.count >= 7, true, name)

        for (cidString, info) in exp.cards {
            let cid = Int64(cidString)!
            guard let card = try col.card(id: cid) else { XCTFail("\(name): missing card \(cid)"); continue }
            XCTAssertEqual(card.ord, info.ord)
            XCTAssertEqual(card.type, info.type, "\(name) card \(cid) type")
            XCTAssertEqual(card.queue, info.queue, "\(name) card \(cid) queue")
            XCTAssertEqual(card.due, info.due, "\(name) card \(cid) due")
            XCTAssertEqual(card.interval, info.ivl)
            XCTAssertEqual(card.factor, info.factor)
            let note = try XCTUnwrap(col.note(id: card.noteId))
            let nt = try XCTUnwrap(col.notetypes[note.notetypeId])
            let rendered = CardRenderer.render(card: card, note: note, notetype: nt, deckName: col.deckName(card.deckId),
                                               mediaExists: { $0.hasPrefix("latex-") })
            XCTAssertEqual(Self.normalizeHintIds(rendered.question), Self.normalizeHintIds(Self.dropLatexNotice(info.question)),
                           "\(name) card \(cid) (\(nt.name) ord \(card.ord)) question")
            XCTAssertEqual(Self.normalizeHintIds(rendered.answer), Self.normalizeHintIds(Self.dropLatexNotice(info.answer)),
                           "\(name) card \(cid) (\(nt.name) ord \(card.ord)) answer")
            XCTAssertEqual(rendered.questionAV.count, info.question_av.count)
            XCTAssertEqual(rendered.answerAV.count, info.answer_av.count)
            for (tag, e) in zip(rendered.questionAV + rendered.answerAV, info.question_av + info.answer_av) {
                switch tag {
                case .sound(let f): XCTAssertEqual(f, e["sound"]?.value as? String)
                case .tts(let text, let lang, let voices, let speed):
                    XCTAssertEqual(text, e["tts"]?.value as? String)
                    XCTAssertEqual(lang, e["lang"]?.value as? String)
                    XCTAssertEqual(voices, e["voices"]?.value as? [String])
                    XCTAssertEqual(speed, e["speed"]?.value as? Double ?? 0, accuracy: 0.001)
                }
            }
        }
    }

    func testModernApkg() throws { try checkPackage("modern.apkg", expectedFormat: .latest) }
    func testLegacyApkg() throws { try checkPackage("legacy.apkg", expectedFormat: .legacy2) }
    func testModernColpkg() throws { try checkPackage("modern.colpkg", expectedFormat: .latest) }
    func testLegacyColpkg() throws { try checkPackage("legacy.colpkg", expectedFormat: .legacy2) }

    func testGenankiAnki2Package() throws {
        let dest = tempDir()
        let summary = try PackageImporter.importPackage(at: Self.fixture("genanki.apkg"), into: dest)
        XCTAssertEqual(summary.format, .legacy1)
        XCTAssertEqual(summary.noteCount, 2)
        XCTAssertEqual(summary.cardCount, 3)
        XCTAssertEqual(summary.mediaCount, 1)
        let col = try AnkiCollection(path: summary.collectionFile, mediaFolder: summary.mediaFolder)
        XCTAssertTrue(col.decks.values.contains { $0.name == "Genanki::Old Deck" })
        let resolver = MediaResolver(folder: summary.mediaFolder)
        var questions: [String] = []
        for cid in try col.allCardIds() {
            let card = try XCTUnwrap(col.card(id: cid))
            let note = try XCTUnwrap(col.note(id: card.noteId))
            let nt = try XCTUnwrap(col.notetypes[note.notetypeId])
            let r = CardRenderer.render(card: card, note: note, notetype: nt, deckName: col.deckName(card.deckId))
            XCTAssertFalse(r.isEmpty)
            questions.append(r.question)
            let page = CardPage.document(card: r, side: .answer, typedAnswer: nil, resolver: resolver, options: .init())
            XCTAssertTrue(page.contains("card\(card.ord + 1)"))
        }
        XCTAssertTrue(questions.contains("Capital of Japan"))
        XCTAssertTrue(questions.contains { $0.contains("<span class=\"cloze\" data-cloze=\"A\" data-ordinal=\"1\">[...]</span>") })
        // v1 scheduler collection without creationOffset must still give a sane day number.
        let timing = col.timingToday()
        XCTAssertGreaterThanOrEqual(timing.daysElapsed, 0)
    }

    func testBareCollectionFile() throws {
        // Extract collection.anki21 from the legacy package and import it on its own.
        let dest = tempDir()
        let summary = try PackageImporter.importPackage(at: Self.fixture("legacy.apkg"), into: dest)
        let dest2 = tempDir()
        let s2 = try PackageImporter.importPackage(at: summary.collectionFile, into: dest2)
        XCTAssertEqual(s2.format, .bareCollection)
        XCTAssertEqual(s2.cardCount, Self.expected.card_count)
    }

    func testRejectsGarbage() throws {
        let dir = tempDir()
        let bad = dir.appendingPathComponent("bad.apkg")
        try Data("hello world, not a deck".utf8).write(to: bad)
        XCTAssertThrowsError(try PackageImporter.importPackage(at: bad, into: dir.appendingPathComponent("out")))
    }
}
