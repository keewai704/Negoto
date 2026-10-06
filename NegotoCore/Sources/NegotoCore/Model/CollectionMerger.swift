import Foundation

/// Merges an imported collection (any Anki schema) into Negoto's single collection,
/// the way Anki imports an .apkg: notes already present (same GUID) are not duplicated,
/// note types/decks/options are added or matched, and scheduling is carried over.
public enum CollectionMerger {
    public struct Summary: Sendable, Equatable {
        public var addedNotes = 0
        public var updatedNotes = 0
        public var skippedNotes = 0
        public var addedCards = 0
        public var addedReviews = 0
        public var addedMedia = 0
        public var renamedMedia = 0
    }

    /// - Parameters:
    ///   - sourceMedia: media folder of the source; files are copied into the target's media folder.
    ///   - now: used to translate day-based due dates between the two collections.
    @discardableResult
    public static func merge(_ source: AnkiCollection, into target: AnkiCollection, sourceMedia: URL? = nil,
                             now: Date = Date()) throws -> Summary {
        precondition(!target.usesSeparateTables, "target must be a schema 11 collection")
        var summary = Summary()
        let nowSecs = Int64(now.timeIntervalSince1970)
        let mediaRenames = try copyMedia(from: sourceMedia ?? source.mediaFolder, to: target.mediaFolder, summary: &summary)
        if !mediaRenames.isEmpty {
            // Point the imported notes at the renamed files (done on the source so a replay sees the same names).
            try source.db.transaction {
                for row in try source.db.query("SELECT id, flds FROM notes") {
                    let renamed = renameMedia(in: row[1].string, mediaRenames)
                    if renamed != row[1].string { try source.db.run("UPDATE notes SET flds = ? WHERE id = ?", [renamed, row[0].int64]) }
                }
            }
        }

        let srcToday = source.timingToday(now: now).daysElapsed
        let dstToday = target.timingToday(now: now).daysElapsed
        let dayShift = Int64(dstToday - srcToday)

        try target.db.transaction {
            // Deck options: add presets that don't exist yet (existing ones keep the user's tweaks).
            var dconf = try target.colJSON("dconf")
            for (id, conf) in source.deckConfigs where dconf[String(id)] == nil {
                var json = AnkiCollection.deckConfigJSON(conf, mod: nowSecs)
                json["usn"] = 0
                dconf[String(id)] = json
            }
            try target.setColJSON("dconf", dconf)

            // Note types: reuse when the id and field/template layout match, otherwise add (with a new id if taken).
            var models = try target.colJSON("models")
            var notetypeMap: [Int64: Int64] = [:]
            for (id, nt) in source.notetypes.sorted(by: { $0.key < $1.key }) {
                if let existing = target.notetypes[id], sameLayout(existing, nt) {
                    notetypeMap[id] = id
                    continue
                }
                if let match = target.notetypes.values.first(where: { $0.name == nt.name && sameLayout($0, nt) }) {
                    notetypeMap[id] = match.id
                    continue
                }
                var newID = id
                while models[String(newID)] != nil || target.notetypes[newID] != nil { newID += 1 }
                var copy = nt
                copy.id = newID
                models[String(newID)] = AnkiCollection.notetypeJSON(copy, mod: nowSecs)
                notetypeMap[id] = newID
            }
            try target.setColJSON("models", models)

            // Decks: matched by name.
            var decks = try target.colJSON("decks")
            var deckByName: [String: Int64] = [:]
            for value in decks.values {
                if let d = value as? [String: Any], let name = d["name"] as? String {
                    deckByName[name] = AnkiCollection.int64(d["id"])
                }
            }
            var deckMap: [Int64: Int64] = [:]
            for deck in source.sortedDecks where !deck.isFiltered {
                // Parents first (sortedDecks is ordered by path).
                if let existing = deckByName[deck.name] {
                    deckMap[deck.id] = existing
                    continue
                }
                var newID = deck.id
                while decks[String(newID)] != nil { newID += 1 }
                var copy = deck
                copy.id = newID
                if dconf[String(copy.configId)] == nil { copy.configId = 1 }
                var json = AnkiCollection.deckJSON(copy, mod: nowSecs)
                json["usn"] = 0
                decks[String(newID)] = json
                deckByName[deck.name] = newID
                deckMap[deck.id] = newID
            }
            // Missing parents of imported decks.
            for name in Array(deckByName.keys) {
                let parts = name.components(separatedBy: "::")
                for i in stride(from: 1, to: parts.count, by: 1) {
                    let parent = parts[0..<i].joined(separator: "::")
                    if deckByName[parent] == nil {
                        var newID = (decks.keys.compactMap(Int64.init).max() ?? 1) + 1
                        while decks[String(newID)] != nil { newID += 1 }
                        var json = AnkiCollection.deckJSON(Deck(id: newID, name: parent, configId: 1, isFiltered: false, description: ""), mod: nowSecs)
                        json["usn"] = 0
                        decks[String(newID)] = json
                        deckByName[parent] = newID
                    }
                }
            }
            try target.setColJSON("decks", decks)

            // Notes
            var existingGUIDs: [String: (id: Int64, mod: Int64)] = [:]
            try target.db.forEach("SELECT guid, id, mod FROM notes") { row in
                existingGUIDs[row[0].string] = (row[1].int64, row[2].int64); return true
            }
            var noteMap: [Int64: Int64] = [:]
            var newNotes = Set<Int64>()
            let rows = try source.db.query("SELECT id, guid, mid, mod, tags, flds, sfld, csum, flags, data FROM notes ORDER BY id")
            for row in rows {
                let srcID = row[0].int64, guid = row[1].string
                let flds = row[5].string
                if let existing = existingGUIDs[guid] {
                    noteMap[srcID] = existing.id
                    if row[3].int64 > existing.mod {
                        try target.db.run("UPDATE notes SET flds = ?, tags = ?, sfld = ?, csum = ?, mod = ?, usn = 0 WHERE id = ?",
                                          [flds, row[4].string, row[6], row[7], row[3].int64, existing.id])
                        summary.updatedNotes += 1
                    } else {
                        summary.skippedNotes += 1
                    }
                    continue
                }
                guard let mid = notetypeMap[row[2].int64] else { continue }
                var newID = srcID
                while try target.db.scalar("SELECT 1 FROM notes WHERE id = ?", [newID]) != .null { newID += 1 }
                try target.db.run("INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) VALUES (?,?,?,?,0,?,?,?,?,?,?)",
                                  [newID, guid, mid, row[3].int64, row[4].string, flds, row[6], row[7], row[8].int, row[9].string])
                noteMap[srcID] = newID
                newNotes.insert(newID)
                existingGUIDs[guid] = (newID, row[3].int64)
                summary.addedNotes += 1
            }

            // Cards: added for new notes, and for existing notes that lack that card.
            let maxNewPos = try target.db.scalar("SELECT max(due) FROM cards WHERE type = 0").int64
            var cardMap: [Int64: Int64] = [:]
            for card in try source.cards(where: "1 ORDER BY id") {
                guard let nid = noteMap[card.noteId] else { continue }
                if !newNotes.contains(nid),
                   try target.db.scalar("SELECT 1 FROM cards WHERE nid = ? AND ord = ?", [nid, card.ord]) != .null {
                    continue
                }
                var c = card
                var newID = card.id
                while try target.db.scalar("SELECT 1 FROM cards WHERE id = ?", [newID]) != .null { newID += 1 }
                c.id = newID
                c.noteId = nid
                c.deckId = deckMap[card.deckId] ?? deckMap[card.originalDeckId] ?? 1
                c.originalDeckId = 0
                c.originalDue = 0
                c.usn = 0
                let dayBased = c.cardType == .review || c.cardType == .relearning && c.queue != Card.Queue.learning.rawValue
                    || c.queue == Card.Queue.dayLearning.rawValue
                if c.cardType == .new {
                    c.due += max(0, maxNewPos)
                } else if dayBased && c.due < 1_000_000_000 {
                    c.due += dayShift
                }
                try target.db.run("""
                    INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data)
                    VALUES (?,?,?,?,?,0,?,?,?,?,?,?,?,?,0,0,?,?)
                    """, [c.id, c.noteId, c.deckId, c.ord, c.mod, c.type, c.queue, c.due, c.interval, c.factor, c.reps,
                          c.lapses, c.left, c.flags, c.data])
                cardMap[card.id] = newID
                summary.addedCards += 1
            }

            // Review history of the added cards.
            for row in try source.db.query("SELECT id, cid, ease, ivl, lastIvl, factor, time, type FROM revlog ORDER BY id") {
                guard let cid = cardMap[row[1].int64] else { continue }
                var id = row[0].int64
                while try target.db.scalar("SELECT 1 FROM revlog WHERE id = ?", [id]) != .null { id += 1 }
                try target.db.run("INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type) VALUES (?,?,0,?,?,?,?,?,?)",
                                  [id, cid, row[2].int, row[3].int, row[4].int, row[5].int, row[6].int, row[7].int])
                summary.addedReviews += 1
            }
        }
        try target.reload()
        return summary
    }

    static func sameLayout(_ a: Notetype, _ b: Notetype) -> Bool {
        a.kind == b.kind && a.fieldNames == b.fieldNames && a.templates.count == b.templates.count
    }

    // MARK: Media

    /// Copies media; a file whose name is taken by different content is stored under a new name.
    static func copyMedia(from src: URL, to dst: URL, summary: inout Summary) throws -> [String: String] {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard src.standardizedFileURL != dst.standardizedFileURL else { return [:] }
        var renames: [String: String] = [:]
        let names = ((try? fm.contentsOfDirectory(atPath: src.path)) ?? []).filter { !$0.hasPrefix(".") }
        for name in names.sorted() {
            let from = src.appendingPathComponent(name)
            var to = dst.appendingPathComponent(name)
            if fm.fileExists(atPath: to.path) {
                if fm.contentsEqual(atPath: from.path, andPath: to.path) { continue }
                let data = (try? Data(contentsOf: from)) ?? Data()
                let hash = String(SHA1.hash([UInt8](data)).prefix(4).map { String(format: "%02x", $0) }.joined())
                let ext = (name as NSString).pathExtension
                let base = (name as NSString).deletingPathExtension
                let newName = ext.isEmpty ? "\(base)-\(hash)" : "\(base)-\(hash).\(ext)"
                renames[name] = newName
                to = dst.appendingPathComponent(newName)
                summary.renamedMedia += 1
                if fm.fileExists(atPath: to.path) { continue }
            }
            try fm.copyItem(at: from, to: to)
            summary.addedMedia += 1
        }
        return renames
    }

    static func renameMedia(in fields: String, _ renames: [String: String]) -> String {
        var out = fields
        for (old, new) in renames where out.contains(old) {
            out = out.replacingOccurrences(of: "\"\(old)\"", with: "\"\(new)\"")
                .replacingOccurrences(of: "'\(old)'", with: "'\(new)'")
                .replacingOccurrences(of: "=\(old)", with: "=\(new)")
                .replacingOccurrences(of: "[sound:\(old)]", with: "[sound:\(new)]")
        }
        return out
    }
}
