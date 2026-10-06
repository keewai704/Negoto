import Foundation

/// Port of Anki's cloze handling (rslib/src/cloze.rs): nested clozes, hints, multiple ordinals,
/// clozes inside MathJax, and image-occlusion shapes.
public enum Cloze {
    indirect enum Node {
        case text(String)
        case cloze(Item)
    }

    struct Item {
        var ordinals: [Int]
        var nodes: [Node]
        var hint: String?

        /// Raw text of the cloze, with nested clozes flattened.
        var clozedText: String {
            nodes.map { node in
                switch node {
                case .text(let t): return t
                case .cloze(let c): return c.clozedText
                }
            }.joined()
        }

        var ordinalString: String { ordinals.map(String.init).joined(separator: ",") }
    }

    // MARK: Parsing

    static func parse(_ text: String) -> [Node] {
        var output: [Node] = []
        var stack: [Item] = []
        var pendingText = ""
        var openPrefixes: [String] = []

        func flushText() {
            guard !pendingText.isEmpty else { return }
            if stack.isEmpty { output.append(.text(pendingText)) } else { stack[stack.count - 1].nodes.append(.text(pendingText)) }
            pendingText = ""
        }

        let scalars = Array(text.unicodeScalars)
        var i = 0
        let n = scalars.count
        while i < n {
            // Opening "{{c<digits>[,<digits>]*::"
            if scalars[i] == "{", i + 3 < n, scalars[i + 1] == "{", scalars[i + 2] == "c" || scalars[i + 2] == "C" {
                var j = i + 3
                var ordinals: [Int] = []
                var current = ""
                var valid = false
                while j < n {
                    let ch = scalars[j]
                    if ("0"..."9").contains(ch) {
                        current.unicodeScalars.append(ch)
                        j += 1
                    } else if ch == ",", !current.isEmpty {
                        ordinals.append(Int(current) ?? 0); current = ""; j += 1
                    } else if ch == ":", j + 1 < n, scalars[j + 1] == ":", !current.isEmpty {
                        ordinals.append(Int(current) ?? 0)
                        j += 2
                        valid = true
                        break
                    } else {
                        break
                    }
                }
                if valid {
                    flushText()
                    var s = ""
                    s.unicodeScalars.append(contentsOf: scalars[i..<j])
                    openPrefixes.append(s)
                    stack.append(Item(ordinals: ordinals.filter { $0 > 0 }.isEmpty ? [0] : ordinals.filter { $0 > 0 }, nodes: [], hint: nil))
                    i = j
                    continue
                }
            }
            if scalars[i] == "}", i + 1 < n, scalars[i + 1] == "}", !stack.isEmpty {
                flushText()
                var item = stack.removeLast()
                openPrefixes.removeLast()
                if case .text(let t)? = item.nodes.last, let range = t.range(of: "::") {
                    item.nodes[item.nodes.count - 1] = .text(String(t[..<range.lowerBound]))
                    item.hint = String(t[range.upperBound...])
                    if case .text(let rest)? = item.nodes.last, rest.isEmpty { item.nodes.removeLast() }
                }
                if stack.isEmpty { output.append(.cloze(item)) } else { stack[stack.count - 1].nodes.append(.cloze(item)) }
                i += 2
                continue
            }
            pendingText.unicodeScalars.append(scalars[i])
            i += 1
        }
        flushText()
        // Unclosed clozes are treated as plain text.
        while let item = stack.popLast() {
            let prefix = openPrefixes.removeLast()
            let nodes: [Node] = [.text(prefix)] + item.nodes
            if stack.isEmpty { output.append(contentsOf: nodes) } else { stack[stack.count - 1].nodes.append(contentsOf: nodes) }
        }
        return output
    }

    // MARK: Rendering

    public static func render(_ text: String, ord: Int, question: Bool) -> String {
        var buf = ""
        var inMathJax = false
        for node in parse(text) {
            switch node {
            case .text(let t):
                buf += t
                inMathJax = mathJaxState(after: t, initial: inMathJax)
            case .cloze(let c):
                if inMathJax {
                    buf += renderInMathJax(c, ord: ord, question: question)
                } else {
                    reveal(c, ord: ord, question: question, into: &buf)
                }
            }
        }
        return buf
    }

    private static func reveal(_ cloze: Item, ord: Int, question: Bool, into buf: inout String) {
        let active = cloze.ordinals.contains(ord)
        if let io = imageOcclusion(cloze) {
            let cls = active ? (question ? "cloze" : "cloze-highlight") : "cloze-inactive"
            buf += "<div class=\"\(cls)\" data-ordinal=\"\(cloze.ordinalString)\" data-shape=\"\(io.shape)\" "
            for (k, v) in io.props {
                let key = k == "oi" ? "occludeInactive" : k
                // Anki only escapes free text; numeric geometry is written verbatim.
                let value = k == "text" ? HTMLText.encodeAttribute(v) : HTMLText.escape(v)
                buf += "data-\(key)=\"\(value)\" "
            }
            buf += "></div>"
            return
        }
        if active && question {
            var content = ""
            for node in cloze.nodes {
                switch node {
                case .text(let t): content += t
                case .cloze(let c): reveal(c, ord: ord, question: false, into: &content)
                }
            }
            let hint = cloze.hint.map { "[\($0)]" } ?? "[...]"
            buf += "<span class=\"cloze\" data-cloze=\"\(HTMLText.encodeAttribute(content))\" data-ordinal=\"\(cloze.ordinalString)\">\(hint)</span>"
            return
        }
        buf += active ? "<span class=\"cloze\" data-ordinal=\"\(cloze.ordinalString)\">"
                      : "<span class=\"cloze-inactive\" data-ordinal=\"\(cloze.ordinalString)\">"
        for node in cloze.nodes {
            switch node {
            case .text(let t): buf += t
            case .cloze(let c): reveal(c, ord: ord, question: question, into: &buf)
            }
        }
        buf += "</span>"
    }

    private static func renderInMathJax(_ cloze: Item, ord: Int, question: Bool) -> String {
        let active = cloze.ordinals.contains(ord)
        let inner = cloze.nodes.map { node -> String in
            switch node {
            case .text(let t): return t
            case .cloze(let c): return renderInMathJax(c, ord: ord, question: question)
            }
        }.joined()
        if active && question {
            return cloze.hint.map { "[\($0)]" } ?? "[...]"
        }
        return inner
    }

    /// Tracks whether we're inside \( \) or \[ \] after the given text.
    private static func mathJaxState(after text: String, initial: Bool) -> Bool {
        var state = initial
        let s = Array(text.unicodeScalars)
        var i = 0
        while i + 1 < s.count {
            if s[i] == "\\" {
                switch s[i + 1] {
                case "(", "[": state = true; i += 2; continue
                case ")", "]": state = false; i += 2; continue
                default: break
                }
            }
            i += 1
        }
        return state
    }

    struct ImageOcclusionShape {
        var shape: String
        var props: [(String, String)]
    }

    static func imageOcclusion(_ cloze: Item) -> ImageOcclusionShape? {
        guard cloze.nodes.count == 1, case .text(let t) = cloze.nodes[0], t.hasPrefix("image-occlusion:") else { return nil }
        var parts = t.dropFirst("image-occlusion:".count).components(separatedBy: ":")
        guard !parts.isEmpty else { return nil }
        let shape = parts.removeFirst()
        let props: [(String, String)] = parts.compactMap { p in
            guard let eq = p.firstIndex(of: "=") else { return nil }
            return (String(p[..<eq]), String(p[p.index(after: eq)...]))
        }
        return ImageOcclusionShape(shape: shape, props: props)
    }

    // MARK: Queries

    /// All cloze ordinals (1-based) referenced in `text`.
    public static func ordinals(in text: String) -> Set<Int> {
        var out = Set<Int>()
        func walk(_ nodes: [Node]) {
            for node in nodes {
                if case .cloze(let c) = node {
                    out.formUnion(c.ordinals)
                    walk(c.nodes)
                }
            }
        }
        walk(parse(text))
        return out
    }

    /// Text of the active clozes, joined with ", " (the `cloze-only` filter and type-in cloze answers).
    public static func onlyText(_ text: String, ord: Int) -> String {
        var found: [String] = []
        func walk(_ nodes: [Node]) {
            for node in nodes {
                if case .cloze(let c) = node {
                    if c.ordinals.contains(ord) { found.append(c.clozedText) }
                    walk(c.nodes)
                }
            }
        }
        walk(parse(text))
        return found.joined(separator: ", ")
    }
}
