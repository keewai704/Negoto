import Foundation

public enum AVTag: Hashable, Sendable {
    case sound(filename: String)
    case tts(text: String, lang: String, voices: [String], speed: Double)
}

public struct RenderedCard: Sendable {
    /// Question HTML containing `[anki:play:q:N]` and `[[type:…]]` markers.
    public var question: String
    public var answer: String
    public var questionAV: [AVTag]
    public var answerAV: [AVTag]
    public var css: String
    /// True if the front side has no visible content.
    public var isEmpty: Bool
    public var cardOrd: Int
    public var isCloze: Bool
    public var fields: [String: String]
}

public enum CardRenderer {
    public static func fieldMap(note: Note, notetype: Notetype) -> [String: String] {
        var map: [String: String] = [:]
        for f in notetype.fields {
            map[f.name] = f.ord < note.fields.count ? note.fields[f.ord] : ""
        }
        return map
    }

    public static func render(card: Card, note: Note, notetype: Notetype, deckName: String,
                              mediaExists: (String) -> Bool = { _ in false }) -> RenderedCard {
        let template = notetype.template(forCardOrd: card.ord)
            ?? CardTemplate(name: "Card", ord: 0, questionFormat: "{{\(notetype.fields.first?.name ?? "Front")}}", answerFormat: "{{FrontSide}}")
        var fields = fieldMap(note: note, notetype: notetype)
        let noteFields = fields
        fields["Tags"] = note.tags.joined(separator: " ")
        fields["Type"] = notetype.name
        fields["Deck"] = deckName
        fields["Subdeck"] = deckName.components(separatedBy: "::").last ?? deckName
        fields["Card"] = template.name
        fields["CardFlag"] = "flag\(card.userFlag)"
        fields["CardID"] = String(card.id)

        var ctx = TemplateContext(fields: fields, cardOrd: card.ord, isQuestion: true)
        if notetype.isCloze { ctx.extraNonEmpty.insert("c\(card.ord + 1)") }

        var q = TemplateEngine.render(template.questionFormat, context: ctx)
        q = LaTeX.render(q, svg: notetype.latexSvg, mediaExists: mediaExists)
        let (qText, qAV) = AVExtraction.extract(q, questionSide: true)

        ctx.isQuestion = false
        ctx.frontSide = qText
        var a = TemplateEngine.render(template.answerFormat, context: ctx)
        a = LaTeX.render(a, svg: notetype.latexSvg, mediaExists: mediaExists)
        let (aText, aAV) = AVExtraction.extract(a, questionSide: false)

        var empty = isVisiblyEmpty(qText) && qAV.isEmpty
        if notetype.isCloze {
            let ordinals = noteFields.values.reduce(into: Set<Int>()) { $0.formUnion(Cloze.ordinals(in: $1)) }
            if !ordinals.contains(card.ord + 1), template.questionFormat.contains("cloze:") { empty = true }
        }
        return RenderedCard(question: qText, answer: aText, questionAV: qAV, answerAV: aAV, css: notetype.css,
                            isEmpty: empty, cardOrd: card.ord, isCloze: notetype.isCloze, fields: noteFields)
    }

    private static let mediaTag = try! NSRegularExpression(pattern: "<(img|video|audio|object|embed|iframe|svg|canvas)\\b", options: .caseInsensitive)

    static func isVisiblyEmpty(_ html: String) -> Bool {
        if mediaTag.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil { return false }
        if html.contains("[[type:") { return false }
        return HTMLText.strip(html).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum AVExtraction {
    private static let regex = try! NSRegularExpression(
        pattern: "\\[sound:(.+?)\\]|\\[anki:tts lang=([^\\]]*)\\](.*?)\\[/anki:tts\\]",
        options: [.dotMatchesLineSeparators])

    public static func extract(_ text: String, questionSide: Bool) -> (String, [AVTag]) {
        var tags: [AVTag] = []
        let side = questionSide ? "q" : "a"
        let out = HTMLText.replace(regex, in: text) { g in
            if let file = g[1] {
                tags.append(.sound(filename: HTMLText.decodeEntities(file)))
            } else {
                tags.append(parseTTS(args: g[2] ?? "", text: g[3] ?? ""))
            }
            return "[anki:play:\(side):\(tags.count - 1)]"
        }
        return (out, tags)
    }

    static func parseTTS(args: String, text: String) -> AVTag {
        var lang = ""
        var voices: [String] = []
        var speed = 1.0
        for (i, part) in args.split(separator: " ").enumerated() {
            if i == 0 && !part.contains("=") { lang = String(part); continue }
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "lang": lang = kv[1]
            case "voices": voices = kv[1].split(separator: ",").map(String.init)
            case "speed": speed = Double(kv[1]) ?? 1
            default: break
            }
        }
        let plain = HTMLText.strip(text.replacingOccurrences(of: "<br>", with: " "))
        return .tts(text: plain, lang: lang, voices: voices, speed: speed)
    }
}

/// `[latex]…[/latex]`, `[$]…[/$]`, `[$$]…[/$$]`. Uses the pre-rendered images Anki ships in the
/// package when present; otherwise falls back to MathJax so the expression is still readable.
public enum LaTeX {
    private static let regex = try! NSRegularExpression(
        pattern: "\\[latex\\](.+?)\\[/latex\\]|\\[\\$\\](.+?)\\[/\\$\\]|\\[\\$\\$\\](.+?)\\[/\\$\\$\\]",
        options: [.dotMatchesLineSeparators, .caseInsensitive])

    public static func filename(for latex: String, svg: Bool) -> String {
        "latex-\(SHA1.hex(latex)).\(svg ? "svg" : "png")"
    }

    public static func render(_ text: String, svg: Bool, mediaExists: (String) -> Bool) -> String {
        guard text.contains("[") else { return text }
        return HTMLText.replace(regex, in: text) { g in
            let latex: String
            let mathjax: String
            if let body = g[1] {
                let t = HTMLText.stripPreservingLineBreaks(body)
                latex = t
                mathjax = fallbackForLatexBlock(t)
            } else if let body = g[2] {
                let t = HTMLText.stripPreservingLineBreaks(body)
                latex = "$" + t + "$"
                mathjax = "\\(" + HTMLText.escape(t) + "\\)"
            } else {
                let t = HTMLText.stripPreservingLineBreaks(g[3] ?? "")
                latex = "\\begin{displaymath}" + t + "\\end{displaymath}"
                mathjax = "\\[" + HTMLText.escape(t) + "\\]"
            }
            let fname = filename(for: latex, svg: svg)
            if mediaExists(fname) {
                return "<img class=latex alt=\"\(HTMLText.encodeAttribute(latex))\" src=\"\(fname)\">"
            }
            let other = filename(for: latex, svg: !svg)
            if mediaExists(other) {
                return "<img class=latex alt=\"\(HTMLText.encodeAttribute(latex))\" src=\"\(other)\">"
            }
            return "<span class=\"latex-fallback\">\(mathjax)</span>"
        }
    }

    /// Converts a LaTeX text-mode snippet into something MathJax can typeset.
    static func fallbackForLatexBlock(_ t: String) -> String {
        var s = t
        if s.contains("$") {
            s = HTMLText.replace(try! NSRegularExpression(pattern: "\\$\\$(.+?)\\$\\$", options: .dotMatchesLineSeparators), in: s) { "\\[" + ($0[1] ?? "") + "\\]" }
            s = HTMLText.replace(try! NSRegularExpression(pattern: "\\$(.+?)\\$", options: .dotMatchesLineSeparators), in: s) { "\\(" + ($0[1] ?? "") + "\\)" }
            return HTMLText.escape(s).replacingOccurrences(of: "\n", with: "<br>")
        }
        if s.contains("\\begin{") { return HTMLText.escape(s) }
        return "\\(" + HTMLText.escape(s) + "\\)"
    }
}
