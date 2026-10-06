import Foundation

/// HTML helpers mirroring the behaviour of Anki's `text.rs`.
public enum HTMLText {
    private static let commentRegex = try! NSRegularExpression(pattern: "<!--.*?-->", options: [.dotMatchesLineSeparators])
    private static let styleScriptRegex = try! NSRegularExpression(
        pattern: "<(style|script)\\b[^>]*>.*?</\\1\\s*>", options: [.dotMatchesLineSeparators, .caseInsensitive])
    private static let tagRegex = try! NSRegularExpression(pattern: "<[^>]*>", options: [.dotMatchesLineSeparators])
    private static let entityRegex = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);?")
    private static let brRegex = try! NSRegularExpression(pattern: "<br\\s*/?>|<div>", options: [.caseInsensitive])

    public static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Replaces each match using a closure. `groups[0]` is the full match; missing groups are nil.
    public static func replace(_ regex: NSRegularExpression, in text: String, using transform: ([String?]) -> String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var groups: [String?] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            out += transform(groups)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Removes all markup (including style/script blocks and comments) and decodes entities.
    public static func strip(_ html: String) -> String {
        var s = replace(commentRegex, in: html, with: "")
        s = replace(styleScriptRegex, in: s, with: "")
        s = replace(tagRegex, in: s, with: "")
        return decodeEntities(s)
    }

    /// Like `strip`, but turns line breaks into newlines (used for LaTeX and type-answer).
    public static func stripPreservingLineBreaks(_ html: String) -> String {
        strip(replace(brRegex, in: html, with: "\n"))
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return replace(entityRegex, in: text) { g in
            let body = g[1] ?? ""
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                if let v = UInt32(body.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { return String(Character(u)) }
            } else if body.hasPrefix("#") {
                if let v = UInt32(body.dropFirst()), let u = Unicode.Scalar(v) { return String(Character(u)) }
            } else if let named = namedEntities[body] {
                return named
            }
            return g[0] ?? ""
        }
    }

    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#x27;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Equivalent of the `htmlescape` crate's `encode_attribute`, which Anki uses for data-* attributes.
    public static func encodeAttribute(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isAlnum = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
            if isAlnum || v >= 256 {
                out.unicodeScalars.append(scalar)
            } else if let named = attributeNamed[v] {
                out += named
            } else {
                let hex = String(v, radix: 16, uppercase: true)
                out += "&#x" + (hex.count < 2 ? "0" + hex : hex) + ";"
            }
        }
        return out
    }

    private static let attributeNamed: [UInt32: String] = [38: "&amp;", 60: "&lt;", 62: "&gt;", 34: "&quot;"]

    /// Anki treats a field as empty if it only contains whitespace, <br> and <div> tags.
    public static func isFieldEmpty(_ text: String) -> Bool {
        replace(emptyFieldRegex, in: text, with: "").isEmpty
    }

    private static let emptyFieldRegex = try! NSRegularExpression(
        pattern: "[\\s\\u200b]+|</?(?:br|div)\\s*/?>", options: [.caseInsensitive])

    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
        "lrm": "\u{200E}", "rlm": "\u{200F}", "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’",
        "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„", "dagger": "†", "Dagger": "‡", "bull": "•",
        "hellip": "…", "permil": "‰", "prime": "′", "Prime": "″", "lsaquo": "‹", "rsaquo": "›", "euro": "€",
        "trade": "™", "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔", "lArr": "⇐",
        "rArr": "⇒", "hArr": "⇔", "iexcl": "¡", "cent": "¢", "pound": "£", "curren": "¤", "yen": "¥",
        "brvbar": "¦", "sect": "§", "uml": "¨", "copy": "©", "ordf": "ª", "laquo": "«", "not": "¬",
        "shy": "\u{AD}", "reg": "®", "macr": "¯", "deg": "°", "plusmn": "±", "sup2": "²", "sup3": "³",
        "acute": "´", "micro": "µ", "para": "¶", "middot": "·", "cedil": "¸", "sup1": "¹", "ordm": "º",
        "raquo": "»", "frac14": "¼", "frac12": "½", "frac34": "¾", "iquest": "¿", "times": "×",
        "divide": "÷", "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å",
        "AElig": "Æ", "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë", "Igrave": "Ì",
        "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï", "ETH": "Ð", "Ntilde": "Ñ", "Ograve": "Ò", "Oacute": "Ó",
        "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø", "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û",
        "Uuml": "Ü", "Yacute": "Ý", "THORN": "Þ", "szlig": "ß", "agrave": "à", "aacute": "á", "acirc": "â",
        "atilde": "ã", "auml": "ä", "aring": "å", "aelig": "æ", "ccedil": "ç", "egrave": "è", "eacute": "é",
        "ecirc": "ê", "euml": "ë", "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï", "eth": "ð",
        "ntilde": "ñ", "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "thorn": "þ", "yuml": "ÿ",
        "OElig": "Œ", "oelig": "œ", "Scaron": "Š", "scaron": "š", "Yuml": "Ÿ", "fnof": "ƒ", "circ": "ˆ",
        "tilde": "˜", "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε", "Zeta": "Ζ",
        "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ", "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ",
        "Omicron": "Ο", "Pi": "Π", "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ",
        "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω", "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
        "epsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ",
        "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π", "rho": "ρ", "sigmaf": "ς", "sigma": "σ",
        "tau": "τ", "upsilon": "υ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω", "forall": "∀",
        "part": "∂", "exist": "∃", "empty": "∅", "nabla": "∇", "isin": "∈", "notin": "∉", "ni": "∋",
        "prod": "∏", "sum": "∑", "minus": "−", "lowast": "∗", "radic": "√", "prop": "∝", "infin": "∞",
        "ang": "∠", "and": "∧", "or": "∨", "cap": "∩", "cup": "∪", "int": "∫", "there4": "∴", "sim": "∼",
        "cong": "≅", "asymp": "≈", "ne": "≠", "equiv": "≡", "le": "≤", "ge": "≥", "sub": "⊂", "sup": "⊃",
        "nsub": "⊄", "sube": "⊆", "supe": "⊇", "oplus": "⊕", "otimes": "⊗", "perp": "⊥", "sdot": "⋅",
        "loz": "◊", "spades": "♠", "clubs": "♣", "hearts": "♥", "diams": "♦",
    ]
}
