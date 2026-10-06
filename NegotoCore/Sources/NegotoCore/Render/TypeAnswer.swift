import Foundation

/// Type-in-the-answer support (`{{type:Field}}`, `{{type:cloze:Field}}`, `{{type:nc:Field}}`).
public enum TypeAnswer {
    static let markerRegex = try! NSRegularExpression(pattern: "\\[\\[type:(.+?)\\]\\]")

    public struct Spec: Equatable {
        public var fieldName: String
        public var cloze: Bool
        public var ignoreCombining: Bool
    }

    public static func spec(in html: String) -> Spec? {
        guard let m = markerRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        var name = String(html[r])
        var cloze = false, nc = false
        if name.hasPrefix("cloze:") { cloze = true; name.removeFirst(6) }
        if name.hasPrefix("nc:") { nc = true; name.removeFirst(3) }
        return Spec(fieldName: name, cloze: cloze, ignoreCombining: nc)
    }

    /// Replaces the first marker with `replacement` and removes the rest.
    public static func replaceMarkers(in html: String, with replacement: String) -> String {
        var first = true
        return HTMLText.replace(markerRegex, in: html) { _ in
            defer { first = false }
            return first ? replacement : ""
        }
    }

    public static func expectedAnswer(spec: Spec, fields: [String: String], cardOrd: Int) -> String {
        var raw = fields[spec.fieldName] ?? fields.first(where: { $0.key.lowercased() == spec.fieldName.lowercased() })?.value ?? ""
        if spec.cloze { raw = Cloze.onlyText(raw, ord: cardOrd + 1) }
        return normalize(HTMLText.stripPreservingLineBreaks(raw))
    }

    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripCombining(_ s: String) -> String {
        String(String.UnicodeScalarView(s.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            !($0.properties.generalCategory == .nonspacingMark || $0.properties.generalCategory == .spacingMark
              || $0.properties.generalCategory == .enclosingMark)
        })).precomposedStringWithCanonicalMapping
    }

    /// HTML comparing what the user typed with the correct answer, styled like Anki
    /// (`typeGood` / `typeBad` / `typeMissed`).
    public static func comparison(typed rawTyped: String, expected rawExpected: String, ignoreCombining: Bool = false) -> String {
        var typed = normalize(rawTyped)
        var expected = rawExpected
        if ignoreCombining {
            typed = stripCombining(typed)
            expected = stripCombining(expected)
        }
        if typed.isEmpty {
            return "<code id=typeans>\(HTMLText.escape(expected).replacingOccurrences(of: "\n", with: "<br>"))</code>"
        }
        if typed == expected {
            return "<code id=typeans><span class=typeGood>\(HTMLText.escape(expected))</span></code>"
        }
        let a = Array(typed), b = Array(expected)
        let (inA, inB) = lcsMembership(a, b)
        let typedHTML = spans(a, inA, good: "typeGood", bad: "typeBad")
        let expectedHTML = spans(b, inB, good: "typeGood", bad: "typeMissed")
        return "<code id=typeans>\(typedHTML)<br><span id=typearrow>&darr;</span><br>\(expectedHTML)</code>"
    }

    private static func spans(_ chars: [Character], _ good: [Bool], good goodClass: String, bad badClass: String) -> String {
        var out = ""
        var i = 0
        while i < chars.count {
            let state = good[i]
            var j = i
            var run = ""
            while j < chars.count && good[j] == state { run.append(chars[j]); j += 1 }
            out += "<span class=\(state ? goodClass : badClass)>\(HTMLText.escape(run))</span>"
            i = j
        }
        return out
    }

    /// Longest-common-subsequence alignment; returns which characters of each side are matched.
    static func lcsMembership(_ a: [Character], _ b: [Character]) -> ([Bool], [Bool]) {
        let n = a.count, m = b.count
        guard n > 0, m > 0, n * m <= 4_000_000 else {
            return ([Bool](repeating: false, count: n), [Bool](repeating: false, count: m))
        }
        var dp = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var inA = [Bool](repeating: false, count: n), inB = [Bool](repeating: false, count: m)
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { inA[i] = true; inB[j] = true; i += 1; j += 1 } else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 } else { j += 1 }
        }
        return (inA, inB)
    }
}
