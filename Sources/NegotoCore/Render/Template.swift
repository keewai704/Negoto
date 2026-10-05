import Foundation

/// Port of Anki's template language (rslib/src/template.rs):
/// `{{Field}}`, `{{filter:...:Field}}`, `{{#Field}}…{{/Field}}`, `{{^Field}}…{{/Field}}`,
/// `{{FrontSide}}` and the legacy `{{=<% %>=}}` alternative delimiters.
public struct TemplateContext {
    public var fields: [String: String]
    /// Keys that count as non-empty for conditionals only (e.g. `c1` on cloze card 1).
    public var extraNonEmpty: Set<String> = []
    /// 0-based card ordinal.
    public var cardOrd: Int
    public var isQuestion: Bool
    public var frontSide: String?

    public init(fields: [String: String], cardOrd: Int, isQuestion: Bool, frontSide: String? = nil) {
        self.fields = fields
        self.cardOrd = cardOrd
        self.isQuestion = isQuestion
        self.frontSide = frontSide
    }

    func lookup(_ key: String) -> String? {
        if let v = fields[key] { return v }
        let lower = key.lowercased()
        return fields.first(where: { $0.key.lowercased() == lower })?.value
    }
}

public enum TemplateEngine {
    indirect enum Node {
        case text(String)
        case replacement(key: String, filters: [String])
        case section(key: String, negated: Bool, children: [Node])
    }

    enum Token {
        case text(String)
        case replacement(String)
        case open(String)
        case openNegated(String)
        case close(String)
    }

    static let altDirective = "{{=<% %>=}}"

    static func tokenize(_ template: String) -> [Token] {
        var open = "{{", close = "}}"
        var body = Substring(template)
        let trimmed = template.drop(while: { $0.isWhitespace })
        if trimmed.hasPrefix(altDirective) {
            body = trimmed.dropFirst(altDirective.count)
            open = "<%"; close = "%>"
        }
        var tokens: [Token] = []
        var rest = body
        while !rest.isEmpty {
            guard let start = rest.range(of: open) else {
                tokens.append(.text(String(rest)))
                break
            }
            guard let end = rest.range(of: close, range: start.upperBound..<rest.endIndex) else {
                tokens.append(.text(String(rest)))
                break
            }
            if start.lowerBound > rest.startIndex { tokens.append(.text(String(rest[..<start.lowerBound]))) }
            let inner = String(rest[start.upperBound..<end.lowerBound])
            tokens.append(classify(inner))
            rest = rest[end.upperBound...]
        }
        return tokens
    }

    static func classify(_ raw: String) -> Token {
        let s = String(raw.drop(while: { $0 == "{" })).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count < 2 { return .replacement(s) }
        if s.hasPrefix("#") { return .open(String(s.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if s.hasPrefix("/") { return .close(String(s.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if s.hasPrefix("^") { return .openNegated(String(s.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        return .replacement(s)
    }

    static func parse(_ template: String) -> [Node] {
        // Each stack frame: (key, negated, children). Frame 0 is the root.
        var stack: [(key: String, negated: Bool, children: [Node])] = [("", false, [])]
        for token in tokenize(template) {
            switch token {
            case .text(let t):
                stack[stack.count - 1].children.append(.text(t))
            case .replacement(let r):
                var parts = r.components(separatedBy: ":")
                let key = parts.removeLast()
                stack[stack.count - 1].children.append(.replacement(key: key, filters: parts.reversed()))
            case .open(let k):
                stack.append((k, false, []))
            case .openNegated(let k):
                stack.append((k, true, []))
            case .close(let k):
                // Be lenient: close the nearest matching section; ignore stray closers.
                guard let idx = stack.lastIndex(where: { $0.key == k }), idx > 0 else { continue }
                while stack.count > idx {
                    let frame = stack.removeLast()
                    stack[stack.count - 1].children.append(.section(key: frame.key, negated: frame.negated, children: frame.children))
                }
            }
        }
        while stack.count > 1 {
            let frame = stack.removeLast()
            stack[stack.count - 1].children.append(.section(key: frame.key, negated: frame.negated, children: frame.children))
        }
        return stack[0].children
    }

    public static func render(_ template: String, context: TemplateContext) -> String {
        var buf = ""
        render(parse(template), context: context, into: &buf)
        return buf
    }

    static func render(_ nodes: [Node], context: TemplateContext, into buf: inout String) {
        for node in nodes {
            switch node {
            case .text(let t):
                buf += t
            case .replacement(let key, let filters):
                if key == "FrontSide" {
                    let fs = context.frontSide ?? ""
                    buf += filters.isEmpty ? fs : TemplateFilters.apply(filters, to: fs, fieldName: key, context: context)
                } else if key.isEmpty {
                    buf += TemplateFilters.apply(filters, to: "", fieldName: key, context: context)
                } else if let value = context.lookup(key) {
                    buf += TemplateFilters.apply(filters, to: value, fieldName: key, context: context)
                } else {
                    let shown = (filters.reversed() + [key]).joined(separator: ":")
                    buf += "<div class=\"negoto-template-error\">{{\(HTMLText.escape(shown))}}: field not found</div>"
                }
            case .section(let key, let negated, let children):
                let nonEmpty: Bool
                if context.extraNonEmpty.contains(key) {
                    nonEmpty = true
                } else if let v = context.lookup(key) {
                    nonEmpty = !HTMLText.isFieldEmpty(v)
                } else {
                    nonEmpty = false
                }
                if nonEmpty != negated { render(children, context: context, into: &buf) }
            }
        }
    }

    /// Field names referenced anywhere in a template (used to tell whether a card would be empty).
    public static func referencedFields(_ template: String) -> Set<String> {
        var out = Set<String>()
        func walk(_ nodes: [Node]) {
            for n in nodes {
                switch n {
                case .replacement(let key, _): out.insert(key)
                case .section(let key, _, let children): out.insert(key); walk(children)
                case .text: break
                }
            }
        }
        walk(parse(template))
        return out
    }
}

/// Built-in field filters (rslib/src/template_filters.rs).
public enum TemplateFilters {
    static func apply(_ filters: [String], to text: String, fieldName: String, context: TemplateContext) -> String {
        var names = filters
        if names == ["cloze", "type"] { names = ["type-cloze"] } else if names == ["nc", "type"] { names = ["type-nc"] }
        var out = text
        for name in names {
            switch name {
            case "text": out = HTMLText.strip(out)
            case "furigana": out = Furigana.furigana(out)
            case "kanji": out = Furigana.kanji(out)
            case "kana": out = Furigana.kana(out)
            case "type": out = "[[type:\(fieldName)]]"
            case "type-cloze": out = "[[type:cloze:\(fieldName)]]"
            case "type-nc": out = "[[type:nc:\(fieldName)]]"
            case "hint": out = hint(out, fieldName: fieldName)
            case "cloze": out = Cloze.render(out, ord: context.cardOrd + 1, question: context.isQuestion)
            case "cloze-only": out = clozeOnly(out, ord: context.cardOrd + 1, question: context.isQuestion)
            case "": break
            default:
                if name.hasPrefix("tts ") {
                    let args = name.dropFirst(4).trimmingCharacters(in: .whitespaces)
                    out = "[anki:tts lang=\(args)]\(out)[/anki:tts]"
                }
                // Unknown filters (usually from add-ons) leave the text unchanged.
            }
        }
        return out
    }

    static func clozeOnly(_ text: String, ord: Int, question: Bool) -> String {
        if !question { return Cloze.onlyText(text, ord: ord) }
        var hints: [String] = []
        func walk(_ nodes: [Cloze.Node]) {
            for node in nodes {
                if case .cloze(let c) = node {
                    if c.ordinals.contains(ord) { hints.append(c.hint ?? "...") }
                    walk(c.nodes)
                }
            }
        }
        walk(Cloze.parse(text))
        return hints.joined(separator: ", ")
    }

    static func hint(_ text: String, fieldName: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        // FNV-1a for a stable DOM id.
        var h: UInt64 = 0xcbf29ce484222325
        for b in (text + "\u{0}" + fieldName).utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let id = String(h, radix: 16)
        return """

        <a class=hint href="#"
        onclick="this.style.display='none';
        document.getElementById('hint\(id)').style.display='block';
        return false;" draggable=false>
        \(fieldName)</a>
        <div id="hint\(id)" class=hint style="display: none">\(text)</div>

        """
    }
}

public enum Furigana {
    private static let regex = try! NSRegularExpression(pattern: " ?([^ >]+?)\\[(.+?)\\]")

    private static func transform(_ text: String, _ f: (String, String) -> String) -> String {
        HTMLText.replace(regex, in: text.replacingOccurrences(of: "&nbsp;", with: " ")) { g in
            let base = g[1] ?? "", reading = g[2] ?? ""
            if reading.hasPrefix("sound:") { return g[0] ?? "" }
            return f(base, reading)
        }
    }

    public static func furigana(_ text: String) -> String {
        transform(text) { "<ruby><rb>\($0)</rb><rt>\($1)</rt></ruby>" }.replacingOccurrences(of: "<rb></rb>", with: "")
    }

    public static func kana(_ text: String) -> String { transform(text) { $1 } }
    public static func kanji(_ text: String) -> String { transform(text) { b, _ in b } }
}
