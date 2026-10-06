import Foundation

/// A subset of Anki's search syntax, translated to SQL over `cards c JOIN notes n`.
///
/// Supported: plain words (with `*` wildcards), "quoted phrases", `-` negation, `or`,
/// `deck:` (with subdecks), `tag:` (with child tags), `note:`, `card:`, `is:new|learn|review|due|suspended|buried`,
/// `flag:`, `prop:ivl|due|reps|lapses|ease` comparisons, `added:`, `rated:`, `nid:`, `cid:` and `field:value`.
public struct CardSearch {
    public var whereClause: String
    public var arguments: [SQLBindable]

    public static let all = CardSearch(whereClause: "1", arguments: [])

    public init(whereClause: String, arguments: [SQLBindable]) {
        self.whereClause = whereClause
        self.arguments = arguments
    }

    /// Splits a query into tokens, keeping quoted parts together (`deck:"My deck"` is one token).
    static func tokenize(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var hasContent = false
        for ch in query {
            if ch == "\"" {
                inQuotes.toggle()
                hasContent = true
                continue
            }
            if !inQuotes && (ch == " " || ch == "\u{3000}" || ch == "\t" || ch == "\n") {
                if hasContent { tokens.append(current) }
                current = ""
                hasContent = false
                continue
            }
            current.append(ch)
            hasContent = true
        }
        if hasContent { tokens.append(current) }
        return tokens
    }

    static func likePattern(_ text: String) -> String {
        var out = ""
        for ch in text {
            switch ch {
            case "%", "_", "\\": out += "\\" + String(ch)
            case "*": out += "%"
            default: out.append(ch)
            }
        }
        return out
    }
}

extension AnkiCollection {
    /// Builds the SQL for a search query.
    public func search(_ query: String, today: Int? = nil) -> CardSearch {
        let tokens = CardSearch.tokenize(query)
        if tokens.isEmpty { return .all }
        let day = today ?? timingToday().daysElapsed
        var groups: [[String]] = [[]]  // OR of ANDs
        var args: [[SQLBindable]] = [[]]
        for token in tokens {
            if token.lowercased() == "or" && !(groups.last?.isEmpty ?? true) {
                groups.append([])
                args.append([])
                continue
            }
            if token.lowercased() == "and" { continue }
            var t = token
            var negate = false
            if t.hasPrefix("-") && t.count > 1 { negate = true; t.removeFirst() }
            var a: [SQLBindable] = []
            let clause = condition(for: t, today: day, args: &a)
            groups[groups.count - 1].append(negate ? "NOT (\(clause))" : "(\(clause))")
            args[args.count - 1] += a
        }
        let parts = groups.filter { !$0.isEmpty }.map { "(" + $0.joined(separator: " AND ") + ")" }
        return CardSearch(whereClause: parts.isEmpty ? "1" : parts.joined(separator: " OR "), arguments: args.flatMap { $0 })
    }

    private func condition(for token: String, today: Int, args: inout [SQLBindable]) -> String {
        guard let colon = token.firstIndex(of: ":"), colon != token.startIndex else { return textCondition(token, args: &args) }
        let key = token[..<colon].lowercased()
        let value = String(token[token.index(after: colon)...])
        switch key {
        case "deck":
            if value == "*" { return "1" }
            let pattern = value.lowercased().replacingOccurrences(of: "::", with: "\u{1f}")
            // A deck matches if it, or one of its parents, matches (so subdecks are included).
            let ids = decks.values.filter { d in
                let comps = d.name.lowercased().components(separatedBy: "::")
                return (1...comps.count).contains { k in
                    Self.wildcardMatch(comps[0..<k].joined(separator: "\u{1f}"), pattern)
                }
            }.map(\.id)
            let list = inClause(ids)
            return "c.did IN \(list) OR c.odid IN \(list)"
        case "tag":
            if value == "none" { return "n.tags = '' OR trim(n.tags) = ''" }
            let p = CardSearch.likePattern(value)
            args += ["% \(p) %", "% \(p)::%"]
            return "n.tags LIKE ? ESCAPE '\\' OR n.tags LIKE ? ESCAPE '\\'"
        case "note", "notetype":
            let ids = notetypes.values.filter { Self.wildcardMatch($0.name.lowercased(), value.lowercased()) }.map(\.id)
            return "n.mid IN \(inClause(ids))"
        case "card":
            if let n = Int(value) { return "c.ord = \(n - 1)" }
            var clauses: [String] = []
            for nt in notetypes.values {
                for t in nt.templates where Self.wildcardMatch(t.name.lowercased(), value.lowercased()) {
                    clauses.append("(n.mid = \(nt.id) AND c.ord = \(t.ord))")
                }
            }
            return clauses.isEmpty ? "0" : clauses.joined(separator: " OR ")
        case "is":
            switch value.lowercased() {
            case "new": return "c.type = 0"
            case "learn": return "c.queue IN (1, 3)"
            case "review": return "c.type IN (2, 3)"
            case "due": return "(c.queue IN (2, 3) AND c.due <= \(today)) OR (c.queue = 1 AND c.due <= \(Int64(Date().timeIntervalSince1970) + Int64(learnAheadSeconds)))"
            case "suspended": return "c.queue = -1"
            case "buried": return "c.queue IN (-2, -3)"
            default: return "0"
            }
        case "flag":
            guard let n = Int(value) else { return "0" }
            return "(c.flags & 7) = \(n)"
        case "nid":
            let ids = value.split(separator: ",").compactMap { Int64($0) }
            return "n.id IN \(inClause(ids))"
        case "cid":
            let ids = value.split(separator: ",").compactMap { Int64($0) }
            return "c.id IN \(inClause(ids))"
        case "added":
            guard let n = Int(value), n > 0 else { return "0" }
            let cutoff = (timingToday().nextDayAt - Int64(n) * 86_400) * 1000
            return "c.id > \(cutoff)"
        case "rated":
            let parts = value.split(separator: ":")
            guard let n = parts.first.flatMap({ Int($0) }), n > 0 else { return "0" }
            let cutoff = (timingToday().nextDayAt - Int64(n) * 86_400) * 1000
            var sub = "SELECT cid FROM revlog WHERE id > \(cutoff)"
            if parts.count > 1, let ease = Int(parts[1]) { sub += " AND ease = \(ease)" }
            return "c.id IN (\(sub))"
        case "prop":
            return propCondition(value, today: today)
        default:
            // field:value
            let fieldName = String(token[..<colon])
            var ords: [(Int64, Int)] = []
            for nt in notetypes.values {
                if let f = nt.fields.first(where: { $0.name.lowercased() == fieldName.lowercased() }) { ords.append((nt.id, f.ord)) }
            }
            guard !ords.isEmpty else { return textCondition(token, args: &args) }
            // Matched in Swift: SQLite can't split fields. Collect matching note ids.
            var matching: [Int64] = []
            let mids = ords.map { String($0.0) }.joined(separator: ",")
            try? db.forEach("SELECT id, mid, flds FROM notes WHERE mid IN (\(mids))") { row in
                let fields = Note.splitFields(row[2].string)
                if let ord = ords.first(where: { $0.0 == row[1].int64 })?.1, ord < fields.count,
                   Self.wildcardMatch(HTMLText.strip(fields[ord]).lowercased(), value.lowercased()) {
                    matching.append(row[0].int64)
                }
                return true
            }
            return "n.id IN \(inClause(matching))"
        }
    }

    private func textCondition(_ text: String, args: inout [SQLBindable]) -> String {
        let p = CardSearch.likePattern(text)
        args.append("%\(p)%")
        return "n.flds LIKE ? ESCAPE '\\'"
    }

    private func propCondition(_ value: String, today: Int) -> String {
        let ops = ["<=", ">=", "!=", "=", "<", ">"]
        guard let op = ops.first(where: { value.contains($0) }), let range = value.range(of: op) else { return "0" }
        let name = value[..<range.lowerBound].lowercased()
        guard let number = Double(value[range.upperBound...]) else { return "0" }
        let sqlOp = op == "=" ? "=" : op
        switch name {
        case "ivl": return "c.ivl \(sqlOp) \(Int(number))"
        case "reps": return "c.reps \(sqlOp) \(Int(number))"
        case "lapses": return "c.lapses \(sqlOp) \(Int(number))"
        case "ease": return "c.factor \(sqlOp) \(Int(number * 1000))"
        case "due": return "c.queue IN (2, 3) AND c.due \(sqlOp) \(today + Int(number))"
        default: return "0"
        }
    }

    /// Case-insensitive match with `*` wildcards (inputs already lowercased).
    static func wildcardMatch(_ text: String, _ pattern: String) -> Bool {
        if !pattern.contains("*") { return text == pattern }
        let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
        return text.range(of: "^" + escaped + "$", options: .regularExpression) != nil
    }

    /// Card ids matching a query, ordered by note creation.
    public func searchCards(_ query: String, limit: Int? = nil, order: String = "n.id, c.ord") throws -> [Int64] {
        let s = search(query)
        var sql = "SELECT c.id FROM cards c JOIN notes n ON n.id = c.nid WHERE \(s.whereClause) ORDER BY \(order)"
        if let limit { sql += " LIMIT \(limit)" }
        return try db.query(sql, s.arguments).map { $0[0].int64 }
    }

    public func countCards(_ query: String) -> Int {
        let s = search(query)
        return (try? db.scalar("SELECT count() FROM cards c JOIN notes n ON n.id = c.nid WHERE \(s.whereClause)", s.arguments).int) ?? 0
    }

    /// Review history of a card, newest first.
    public func reviewHistory(cardID: Int64, limit: Int = 50) -> [RevlogEntry] {
        ((try? db.query("SELECT id, cid, usn, ease, ivl, lastIvl, factor, time, type FROM revlog WHERE cid = ? ORDER BY id DESC LIMIT \(limit)", [cardID])) ?? [])
            .map { r in
                RevlogEntry(id: r[0].int64, cardId: r[1].int64, usn: r[2].int, ease: r[3].int, interval: r[4].int,
                            lastInterval: r[5].int, factor: r[6].int, time: r[7].int, type: r[8].int)
            }
    }
}
