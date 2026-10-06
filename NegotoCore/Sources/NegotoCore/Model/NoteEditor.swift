import Foundation

public enum NoteEditError: Error, LocalizedError, Equatable {
    case noCards
    case noClozes
    case missingNotetype
    case missingNote

    public var errorDescription: String? {
        switch self {
        case .noCards: return "カードが作られません。表面に使われるフィールドを入力してください。"
        case .noClozes: return "穴埋め（{{c1::…}}）がありません。"
        case .missingNotetype: return "ノートタイプが見つかりません。"
        case .missingNote: return "ノートが見つかりません。"
        }
    }
}

/// Adding, editing and deleting notes in Negoto's (schema 11) collection.
/// Every change is marked with usn = -1 so that it is synced to other devices.
extension AnkiCollection {
    private var nowSecs: Int64 { Int64(Date().timeIntervalSince1970) }

    // MARK: Card generation

    /// Card ordinals that a note with these fields produces (Anki's rule: a template makes a card
    /// when its front side has content coming from the note; a cloze note makes one card per cloze number).
    public func cardOrdinals(notetype nt: Notetype, fields: [String]) -> [Int] {
        var map: [String: String] = [:]
        for f in nt.fields { map[f.name] = f.ord < fields.count ? fields[f.ord] : "" }
        if nt.isCloze {
            guard let template = nt.templates.first else { return [] }
            let clozeFields = Self.clozeFieldNames(template.questionFormat)
            var ordinals = Set<Int>()
            for (name, value) in map where clozeFields.isEmpty || clozeFields.contains(name) {
                ordinals.formUnion(Cloze.ordinals(in: value))
            }
            return ordinals.filter { $0 > 0 }.map { $0 - 1 }.sorted()
        }
        var emptyMap = map
        for key in emptyMap.keys { emptyMap[key] = "" }
        return nt.templates.sorted { $0.ord < $1.ord }.compactMap { t in
            let filled = TemplateEngine.render(t.questionFormat, context: TemplateContext(fields: map, cardOrd: t.ord, isQuestion: true))
            let empty = TemplateEngine.render(t.questionFormat, context: TemplateContext(fields: emptyMap, cardOrd: t.ord, isQuestion: true))
            guard !CardRenderer.isVisiblyEmpty(filled), filled != empty else { return nil }
            return t.ord
        }
    }

    private static let clozeRef = try! NSRegularExpression(pattern: "\\{\\{[^}]*cloze:([^}]+)\\}\\}")

    static func clozeFieldNames(_ template: String) -> Set<String> {
        let ns = template as NSString
        return Set(clozeRef.matches(in: template, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces)
        })
    }

    // MARK: Adding

    /// Adds a note and its cards to `deckId`. Returns the new note id.
    @discardableResult
    public func addNote(notetypeId: Int64, deckId: Int64, fields rawFields: [String], tags: [String]) throws -> Int64 {
        guard let nt = notetypes[notetypeId] else { throw NoteEditError.missingNotetype }
        let fields = Self.normalizedFields(rawFields, count: nt.fields.count)
        let ordinals = cardOrdinals(notetype: nt, fields: fields)
        if ordinals.isEmpty { throw nt.isCloze ? NoteEditError.noClozes : NoteEditError.noCards }
        let now = nowSecs
        var noteID = Int64(Date().timeIntervalSince1970 * 1000)
        try db.transaction {
            while !(try db.scalar("SELECT 1 FROM notes WHERE id = ?", [noteID])).isNull { noteID += 1 }
            let (sfld, csum) = Self.sortFieldAndChecksum(nt, fields)
            try db.run("INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) VALUES (?,?,?,?,-1,?,?,?,?,0,'')",
                       [noteID, Self.newGUID(), notetypeId, now, Self.tagString(tags), fields.joined(separator: "\u{1f}"), sfld, csum])
            var position = try takeNewPositions(1)
            if position <= 0 { position = 1 }
            for ord in ordinals { try insertNewCard(noteID: noteID, deckID: deckId, ord: ord, due: position) }
        }
        markModified()
        return noteID
    }

    /// Updates a note's fields and tags; creates cards for templates/clozes that became non-empty.
    /// Returns the number of new cards.
    @discardableResult
    public func updateNote(id: Int64, fields rawFields: [String], tags: [String]) throws -> Int {
        guard let note = try note(id: id) else { throw NoteEditError.missingNote }
        guard let nt = notetypes[note.notetypeId] else { throw NoteEditError.missingNotetype }
        let fields = Self.normalizedFields(rawFields, count: nt.fields.count)
        let existing = try db.query("SELECT ord, did FROM cards WHERE nid = ? ORDER BY ord", [id])
        let existingOrds = Set(existing.map { $0[0].int })
        let deck = existing.first?[1].int64 ?? 1
        let missing = cardOrdinals(notetype: nt, fields: fields).filter { !existingOrds.contains($0) }
        if fields == note.fields && Set(tags) == Set(note.tags) && missing.isEmpty { return 0 }
        try db.transaction {
            let (sfld, csum) = Self.sortFieldAndChecksum(nt, fields)
            try db.run("UPDATE notes SET flds = ?, sfld = ?, csum = ?, tags = ?, mod = ?, usn = -1 WHERE id = ?",
                       [fields.joined(separator: "\u{1f}"), sfld, csum, Self.tagString(tags), max(nowSecs, note.mod + 1), id])
            if !missing.isEmpty {
                let position = try takeNewPositions(1)
                for ord in missing { try insertNewCard(noteID: id, deckID: deck, ord: ord, due: position) }
            }
        }
        markModified()
        return missing.count
    }

    /// Moves cards to another deck.
    public func moveCards(_ ids: [Int64], toDeck deckId: Int64) throws {
        guard !ids.isEmpty else { return }
        let now = nowSecs
        try db.transaction {
            for id in ids {
                try db.run("UPDATE cards SET did = ?, mod = max(mod + 1, ?), usn = -1 WHERE id = ? AND did != ?", [deckId, now, id, deckId])
            }
        }
        markModified()
    }

    /// Deletes notes with all their cards. Deletions are remembered so they can be synced.
    public func deleteNotes(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try db.execute("CREATE TABLE IF NOT EXISTS negoto_deleted_notes (id INTEGER PRIMARY KEY)")
        try db.transaction {
            for id in ids {
                try db.run("DELETE FROM cards WHERE nid = ?", [id])
                try db.run("DELETE FROM notes WHERE id = ?", [id])
                try db.run("INSERT OR IGNORE INTO negoto_deleted_notes (id) VALUES (?)", [id])
            }
        }
        markModified()
    }

    /// Every tag used in the collection, sorted.
    public func allTags() -> [String] {
        var tags = Set<String>()
        try? db.forEach("SELECT DISTINCT tags FROM notes WHERE tags != ''") { row in
            for t in Note.splitTags(row[0].string) { tags.insert(t) }
            return true
        }
        return tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Helpers

    private func insertNewCard(noteID: Int64, deckID: Int64, ord: Int, due: Int64) throws {
        var cardID = Int64(Date().timeIntervalSince1970 * 1000)
        while !(try db.scalar("SELECT 1 FROM cards WHERE id = ?", [cardID])).isNull { cardID += 1 }
        try db.run("""
            INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data)
            VALUES (?,?,?,?,?,-1,0,0,?,0,0,0,0,0,0,0,0,'')
            """, [cardID, noteID, deckID, ord, nowSecs, due])
    }

    /// Reserves `count` positions in the new-card queue (the collection's "nextPos").
    private func takeNewPositions(_ count: Int) throws -> Int64 {
        var conf = try colJSON("conf")
        let fromCards = (try db.scalar("SELECT max(due) FROM cards WHERE type = 0").int64) + 1
        let next = max(Self.int64(conf["nextPos"]), fromCards, 1)
        conf["nextPos"] = next + Int64(count)
        try setColJSON("conf", conf)
        return next
    }

    static func normalizedFields(_ fields: [String], count: Int) -> [String] {
        var out = Array(fields.prefix(count)).map { $0.replacingOccurrences(of: "\u{1f}", with: "") }
        while out.count < count { out.append("") }
        return out
    }

    static func tagString(_ tags: [String]) -> String {
        var seen = Set<String>()
        let cleaned = tags.flatMap { Note.splitTags($0) }.filter { seen.insert($0.lowercased()).inserted }
        return cleaned.isEmpty ? "" : " " + cleaned.joined(separator: " ") + " "
    }

    static func sortFieldAndChecksum(_ nt: Notetype, _ fields: [String]) -> (String, Int64) {
        let ordered = nt.fields.sorted { $0.ord < $1.ord }
        func value(_ i: Int) -> String {
            guard i < ordered.count, ordered[i].ord < fields.count else { return fields.first ?? "" }
            return fields[ordered[i].ord]
        }
        let sort = HTMLText.strip(value(nt.sortFieldIndex))
        let first = HTMLText.strip(value(0))
        let csum = Int64(SHA1.hex(first).prefix(8), radix: 16) ?? 0
        return (sort, csum)
    }

    private static let guidChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~")

    /// Anki's base91 guid of a random 64-bit number.
    static func newGUID() -> String {
        var n = UInt64.random(in: 0...UInt64.max)
        var out = ""
        repeat {
            out.append(guidChars[Int(n % UInt64(guidChars.count))])
            n /= UInt64(guidChars.count)
        } while n > 0
        return String(out.reversed())
    }
}
