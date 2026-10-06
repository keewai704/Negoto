import Foundation
import XCTest
@testable import NegotoCore

final class RenderTests: XCTestCase {
    func render(_ template: String, _ fields: [String: String], ord: Int = 0, question: Bool = true, front: String? = nil) -> String {
        TemplateEngine.render(template, context: TemplateContext(fields: fields, cardOrd: ord, isQuestion: question, frontSide: front))
    }

    func testSectionsAndFilters() {
        let f = ["Front": "a<b>b</b>&amp;", "Empty": "<br> <div></div>", "Tags": "x"]
        XCTAssertEqual(render("{{#Front}}Y{{/Front}}{{^Front}}N{{/Front}}", f), "Y")
        XCTAssertEqual(render("{{#Empty}}Y{{/Empty}}{{^Empty}}N{{/Empty}}", f), "N")
        XCTAssertEqual(render("{{text:Front}}", f), "ab&")
        XCTAssertEqual(render("{{{Front}}}", f), "a<b>b</b>&amp;}")
        XCTAssertEqual(render("{{ Front }}", f), "a<b>b</b>&amp;")
        XCTAssertEqual(render("{{unknownfilter:Front}}", f), "a<b>b</b>&amp;")
        XCTAssertEqual(render("{{#Tags}}T{{/Tags}}", f), "T")
        XCTAssertEqual(render("{{FrontSide}}", f, question: false, front: "Q"), "Q")
        XCTAssertEqual(render("{{type:Front}}", f), "[[type:Front]]")
        XCTAssertEqual(render("{{type:cloze:Front}}", f), "[[type:cloze:Front]]")
        XCTAssertEqual(render("{{type:nc:Front}}", f), "[[type:nc:Front]]")
    }

    func testMalformedTemplatesDoNotCrash() {
        let f = ["A": "1"]
        XCTAssertEqual(render("{{#A}}open", f), "open")
        XCTAssertEqual(render("stray{{/A}}x", f), "strayx")
        XCTAssertEqual(render("{{A", f), "{{A")
        XCTAssertEqual(render("{{#A}}{{^B}}x{{/A}}", f), "x")
        XCTAssertTrue(render("{{Missing}}", f).contains("field not found"))
        XCTAssertEqual(render("", f), "")
        XCTAssertEqual(render("{{}}", f), "")
        // Field names are matched case-insensitively as a fallback.
        XCTAssertEqual(render("{{a}}", f), "1")
    }

    func testClozeEdgeCases() {
        XCTAssertEqual(Cloze.render("{{c1::a}} {{c1::unclosed", ord: 1, question: false),
                       "<span class=\"cloze\" data-ordinal=\"1\">a</span> {{c1::unclosed")
        XCTAssertEqual(Cloze.render("no clozes }} here", ord: 1, question: true), "no clozes }} here")
        XCTAssertEqual(Cloze.ordinals(in: "{{c1::a}}{{c12::b}}{{c2,3::c}}"), [1, 12, 2, 3])
        XCTAssertEqual(Cloze.onlyText("{{c1::a::h}} {{c2::b}} {{c1::c}}", ord: 1), "a, c")
        XCTAssertEqual(Cloze.render("\\(x={{c1::y::h}}\\)", ord: 1, question: true), "\\(x=[h]\\)")
    }

    func testFurigana() {
        XCTAssertEqual(Furigana.furigana("日本[にほん]"), "<ruby><rb>日本</rb><rt>にほん</rt></ruby>")
        XCTAssertEqual(Furigana.kana(" 日本[にほん]語"), "にほん語")
        XCTAssertEqual(Furigana.kanji("日本[にほん]"), "日本")
        XCTAssertEqual(Furigana.furigana("[sound:x.mp3]"), "[sound:x.mp3]")
    }

    func testTypeAnswerComparison() {
        XCTAssertEqual(TypeAnswer.comparison(typed: "Paris", expected: "Paris"),
                       "<code id=typeans><span class=typeGood>Paris</span></code>")
        let cmp = TypeAnswer.comparison(typed: "Pariss", expected: "Paris")
        XCTAssertTrue(cmp.contains("<span class=typeBad>s</span>"))
        XCTAssertTrue(cmp.contains("typearrow"))
        XCTAssertEqual(TypeAnswer.comparison(typed: "", expected: "a<b"), "<code id=typeans>a&lt;b</code>")
        XCTAssertEqual(TypeAnswer.comparison(typed: "uber", expected: "über", ignoreCombining: true),
                       "<code id=typeans><span class=typeGood>uber</span></code>")
        let spec = TypeAnswer.spec(in: "x [[type:cloze:Text]]")
        XCTAssertEqual(spec, TypeAnswer.Spec(fieldName: "Text", cloze: true, ignoreCombining: false))
        XCTAssertEqual(TypeAnswer.expectedAnswer(spec: spec!, fields: ["Text": "{{c1::Tokyo}} {{c2::x}}"], cardOrd: 0), "Tokyo")
    }

    func testLatexFallbackAndImages() {
        let withImage = LaTeX.render("[$]x^2[/$]", svg: false, mediaExists: { _ in true })
        XCTAssertTrue(withImage.hasPrefix("<img class=latex"))
        let fallback = LaTeX.render("[$$]x<y[/$$] [latex]$a$ text[/latex]", svg: false, mediaExists: { _ in false })
        XCTAssertTrue(fallback.contains("\\[x&lt;y\\]"))
        XCTAssertTrue(fallback.contains("\\(a\\) text"))
    }

    func testMediaResolverRewritesReferences() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // NFD on disk, NFC in the HTML; '#' and spaces in names; case mismatch.
        for name in ["cafe\u{301} #1.jpg", "a b.png", "Photo.JPG", "_font.ttf"] {
            try Data([1]).write(to: dir.appendingPathComponent(name))
        }
        let r = MediaResolver(folder: dir)
        XCTAssertEqual(r.resolve("café #1.jpg"), "cafe\u{301} #1.jpg")
        XCTAssertEqual(r.resolve("a%20b.png"), "a b.png")
        XCTAssertEqual(r.resolve("photo.jpg"), "Photo.JPG")
        XCTAssertNil(r.resolve("missing.png"))
        let html = r.rewriteReferences(in: "<img src=\"a b.png\"><img src='photo.jpg'><a href=\"#\">x</a><img src=https://x/y.png><img src=\"missing.png\">")
        XCTAssertEqual(html, "<img src=\"a%20b.png\"><img src=\"Photo.JPG\"><a href=\"#\">x</a><img src=https://x/y.png><img src=\"missing.png\">")
        XCTAssertEqual(r.rewriteCSS("src: url('_font.ttf')"), "src: url(\"_font.ttf\")")
        XCTAssertTrue(r.rewriteReferences(in: "<img src=\"café #1.jpg\">").contains("%231.jpg"))
    }

    func testCardPageContainsPlayButtonsAndTypeBox() {
        let card = RenderedCard(question: "Q [anki:play:q:0] [[type:Back]]", answer: "A [anki:play:a:0] [[type:Back]] [anki:play:a:1]",
                                questionAV: [.sound(filename: "a.mp3")], answerAV: [.sound(filename: "b.mp3"), .sound(filename: "v.mp4")],
                                css: ".card{}", isEmpty: false, cardOrd: 0, isCloze: false, fields: ["Back": "Paris"])
        let q = CardPage.body(for: card, side: .question, typedAnswer: nil, resolver: nil)
        XCTAssertTrue(q.contains("replay-button"))
        XCTAssertTrue(q.contains("<input type=\"text\" id=\"typeans\""))
        let a = CardPage.body(for: card, side: .answer, typedAnswer: "Paris", resolver: nil)
        XCTAssertTrue(a.contains("typeGood"))
        XCTAssertTrue(a.contains("<video"))
        let doc = CardPage.document(card: card, side: .answer, typedAnswer: nil, resolver: nil,
                                    options: .init(nightMode: true, isPad: true, supportBaseURL: "file:///x/"))
        XCTAssertTrue(doc.contains("class=\"card card1 mobile ios ipad nightMode night_mode\""))
        XCTAssertTrue(doc.contains("file:///x/mathjax/tex-svg-full.js"))
    }

    func testOggDecoderRejectsGarbage() {
        XCTAssertNil(OggVorbis.decodeToWAV(Data("OggS-not-really".utf8)))
    }

    func testProtobufPackedFloats() {
        // field 1, packed: [1.0, 10.0]
        var d = Data([0x0A, 0x08])
        for f: Float in [1, 10] { withUnsafeBytes(of: f.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: [0x48, 0x14]) // field 9 varint 20
        let m = ProtoMessage(d)
        XCTAssertEqual(m.floats(1), [1, 10])
        XCTAssertEqual(m.uint(9), 20)
    }

    func testTimingRollover() {
        let utc = TimeZone(identifier: "UTC")!
        // Created 2024-01-01 10:00 UTC, rollover 4am.
        let crt: Int64 = 1_704_103_200
        let t1 = SchedTimingToday.compute(creationSecs: crt, creationOffsetMinutesWest: 0, nowSecs: crt + 86_400,
                                          timeZone: utc, rolloverHour: 4, schedulerVersion: 2)
        XCTAssertEqual(t1.daysElapsed, 1)
        // 2024-01-03 03:00 is still "day 1" because the day starts at 4am.
        let t2 = SchedTimingToday.compute(creationSecs: crt, creationOffsetMinutesWest: 0, nowSecs: 1_704_250_800,
                                          timeZone: utc, rolloverHour: 4, schedulerVersion: 2)
        XCTAssertEqual(t2.daysElapsed, 1)
        XCTAssertEqual(t2.nextDayAt, 1_704_254_400)
    }
}

final class AudioTests: XCTestCase {
    func testOggVorbisDecodesToWAV() throws {
        let url = Bundle.module.url(forResource: "tone.ogg", withExtension: nil, subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        XCTAssertTrue(OggVorbis.isOgg(data))
        let wav = try XCTUnwrap(OggVorbis.decodeToWAV(data))
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        // ~0.3s mono 22.05kHz 16-bit
        XCTAssertGreaterThan(wav.count, 44 + 10_000)
    }
}
