import Foundation

public enum CollectionError: Error, LocalizedError {
    case notAnAnkiCollection
    case missingData(String)

    public var errorDescription: String? {
        switch self {
        case .notAnAnkiCollection: return "The file is not an Anki collection."
        case .missingData(let s): return "The collection is missing data: \(s)"
        }
    }
}

/// An opened Anki collection database (any schema from Anki 2.0's v11 to the current v18).
/// The app studies directly inside the imported collection so that every note type, deck
/// option and scheduling state is preserved exactly.
public final class AnkiCollection {
    public let db: SQLiteDatabase
    public let mediaFolder: URL
    public private(set) var schemaVersion: Int = 11
    public private(set) var creationTime: Int64 = 0
    public private(set) var notetypes: [Int64: Notetype] = [:]
    public private(set) var decks: [Int64: Deck] = [:]
    public private(set) var deckConfigs: [Int64: DeckConfig] = [:]
    public private(set) var config: [String: Any] = [:]

    public init(path: URL, mediaFolder: URL) throws {
        self.db = try SQLiteDatabase(path: path.path)
        self.mediaFolder = mediaFolder
        guard db.tableExists("col"), db.tableExists("cards"), db.tableExists("notes") else {
            throw CollectionError.notAnAnkiCollection
        }
        try reload()
    }

    public var usesSeparateTables: Bool { db.tableExists("notetypes") }

    public func reload() throws {
        guard let col = try db.query("SELECT * FROM col LIMIT 1").first else {
            throw CollectionError.missingData("col")
        }
        schemaVersion = col["ver"].int
        creationTime = col["crt"].int64
        if usesSeparateTables {
            try loadModernTables(col)
        } else {
            try loadLegacyJSON(col)
        }
    }

    // MARK: - Schema 11 (JSON in the col table)

    private static func json(_ value: SQLValue) -> [String: Any] {
        let s = value.string
        guard !s.isEmpty, let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return [:] }
        return obj
    }

    private func loadLegacyJSON(_ col: SQLRow) throws {
        config = Self.json(col["conf"])
        notetypes = [:]
        for (_, any) in Self.json(col["models"]) {
            guard let m = any as? [String: Any] else { continue }
            let id = Self.int64(m["id"])
            let fields = (m["flds"] as? [[String: Any]] ?? []).enumerated().map { i, f in
                NoteField(name: f["name"] as? String ?? "Field \(i + 1)", ord: Self.int(f["ord"]) ?? i)
            }
            let templates = (m["tmpls"] as? [[String: Any]] ?? []).enumerated().map { i, t in
                CardTemplate(name: t["name"] as? String ?? "Card \(i + 1)", ord: Self.int(t["ord"]) ?? i,
                             questionFormat: t["qfmt"] as? String ?? "", answerFormat: t["afmt"] as? String ?? "")
            }
            notetypes[id] = Notetype(
                id: id, name: m["name"] as? String ?? "Note Type",
                kind: Self.int(m["type"]) == 1 ? .cloze : .normal,
                css: m["css"] as? String ?? "", fields: fields, templates: templates,
                sortFieldIndex: Self.int(m["sortf"]) ?? 0,
                latexPre: m["latexPre"] as? String ?? "", latexPost: m["latexPost"] as? String ?? "",
                latexSvg: (m["latexsvg"] as? Bool) ?? false)
        }
        decks = [:]
        for (_, any) in Self.json(col["decks"]) {
            guard let d = any as? [String: Any] else { continue }
            let id = Self.int64(d["id"])
            decks[id] = Deck(
                id: id, name: (d["name"] as? String ?? "Deck").replacingOccurrences(of: "\u{1f}", with: "::"),
                configId: Self.int64(d["conf"] ?? 1), isFiltered: Self.int(d["dyn"]) == 1,
                description: d["desc"] as? String ?? "",
                newLimit: Self.int(d["newLimit"]), reviewLimit: Self.int(d["reviewLimit"]))
        }
        deckConfigs = [:]
        for (_, any) in Self.json(col["dconf"]) {
            guard let c = any as? [String: Any] else { continue }
            let conf = Self.deckConfig(fromLegacy: c)
            deckConfigs[conf.id] = conf
        }
    }

    static func deckConfig(fromLegacy c: [String: Any]) -> DeckConfig {
        var conf = DeckConfig(id: int64(c["id"] ?? 1), name: c["name"] as? String ?? "Default")
        let new = c["new"] as? [String: Any] ?? [:]
        let rev = c["rev"] as? [String: Any] ?? [:]
        let lapse = c["lapse"] as? [String: Any] ?? [:]
        if let delays = new["delays"] as? [Any] { conf.learnSteps = delays.compactMap(double) }
        if let ints = new["ints"] as? [Any] {
            let v = ints.compactMap(int)
            if v.count > 0 { conf.graduatingIntervalGood = v[0] }
            if v.count > 1 { conf.graduatingIntervalEasy = v[1] }
        }
        if let f = double(new["initialFactor"]) { conf.initialEase = f / 1000 }
        if let p = int(new["perDay"]) { conf.newPerDay = p }
        if let b = new["bury"] as? Bool { conf.buryNew = b }
        if let p = int(rev["perDay"]) { conf.reviewsPerDay = p }
        if let e = double(rev["ease4"]) { conf.easyMultiplier = e }
        if let f = double(rev["ivlFct"]) { conf.intervalMultiplier = f }
        if let m = int(rev["maxIvl"]) { conf.maximumReviewInterval = m }
        if let h = double(rev["hardFactor"]) { conf.hardMultiplier = h }
        if let b = rev["bury"] as? Bool { conf.buryReviews = b }
        if let delays = lapse["delays"] as? [Any] { conf.relearnSteps = delays.compactMap(double) }
        if let m = double(lapse["mult"]) { conf.lapseMultiplier = m }
        if let m = int(lapse["minInt"]) { conf.minimumLapseInterval = m }
        if let l = int(lapse["leechFails"]) { conf.leechThreshold = l }
        if let a = int(lapse["leechAction"]) { conf.leechAction = DeckConfig.LeechAction(rawValue: a) ?? .tagOnly }
        if let autoplay = c["autoplay"] as? Bool { conf.disableAutoplay = !autoplay }
        if let replayq = c["replayq"] as? Bool { conf.skipQuestionWhenReplayingAnswer = !replayq }
        if let t = int(c["maxTaken"]) { conf.capAnswerTimeToSecs = t }
        if let m = int(c["newMix"]) { conf.newMix = DeckConfig.NewMix(rawValue: m) ?? .mixWithReviews }
        if let b = c["buryInterdayLearning"] as? Bool { conf.buryInterdayLearning = b }
        if let r = double(c["desiredRetention"]) { conf.desiredRetention = r }
        for key in ["fsrsParams6", "fsrsParams5", "fsrsWeights"] {
            if let w = c[key] as? [Any], !w.isEmpty { conf.fsrsParams = w.compactMap(double); break }
        }
        return conf
    }

    // MARK: - Schema 15+ (separate tables with protobuf configs)

    private func loadModernTables(_ col: SQLRow) throws {
        config = [:]
        if db.tableExists("config") {
            for row in try db.query("SELECT KEY, val FROM config") {
                let data = row["val"].data
                if let v = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    config[row["KEY"].string] = v
                }
            }
        }
        var fieldsByType: [Int64: [NoteField]] = [:]
        for row in try db.query("SELECT ntid, ord, name FROM fields ORDER BY ntid, ord") {
            fieldsByType[row["ntid"].int64, default: []].append(NoteField(name: row["name"].string, ord: row["ord"].int))
        }
        var templatesByType: [Int64: [CardTemplate]] = [:]
        for row in try db.query("SELECT ntid, ord, name, config FROM templates ORDER BY ntid, ord") {
            let cfg = ProtoMessage(row["config"].data)
            templatesByType[row["ntid"].int64, default: []].append(CardTemplate(
                name: row["name"].string, ord: row["ord"].int,
                questionFormat: cfg.string(1) ?? "", answerFormat: cfg.string(2) ?? ""))
        }
        notetypes = [:]
        for row in try db.query("SELECT id, name, config FROM notetypes") {
            let id = row["id"].int64
            let cfg = ProtoMessage(row["config"].data)
            notetypes[id] = Notetype(
                id: id, name: row["name"].string, kind: cfg.uint(1) == 1 ? .cloze : .normal,
                css: cfg.string(3) ?? "", fields: fieldsByType[id] ?? [], templates: templatesByType[id] ?? [],
                sortFieldIndex: Int(cfg.uint(2) ?? 0), latexPre: cfg.string(5) ?? "",
                latexPost: cfg.string(6) ?? "", latexSvg: cfg.bool(7) ?? false)
        }
        decks = [:]
        for row in try db.query("SELECT id, name, kind FROM decks") {
            let id = row["id"].int64
            let kind = ProtoMessage(row["kind"].data)
            let normal = kind.message(1)
            decks[id] = Deck(
                id: id, name: row["name"].string.replacingOccurrences(of: "\u{1f}", with: "::"),
                configId: normal?.int(1) ?? 1, isFiltered: kind.has(2) && normal == nil,
                description: normal?.string(4) ?? "",
                newLimit: (normal?.uint(7)).map { Int($0) }, reviewLimit: (normal?.uint(6)).map { Int($0) })
        }
        deckConfigs = [:]
        for row in try db.query("SELECT id, name, config FROM deck_config") {
            let id = row["id"].int64
            let m = ProtoMessage(row["config"].data)
            var c = DeckConfig(id: id, name: row["name"].string)
            c.learnSteps = m.floats(1).map(Double.init)
            c.relearnSteps = m.floats(2).map(Double.init)
            if let v = m.uint(9) { c.newPerDay = Int(v) } else { c.newPerDay = 0 }
            if let v = m.uint(10) { c.reviewsPerDay = Int(v) } else { c.reviewsPerDay = 0 }
            c.initialEase = Double(m.float(11) ?? 2.5)
            c.easyMultiplier = Double(m.float(12) ?? 1.3)
            c.hardMultiplier = Double(m.float(13) ?? 1.2)
            c.lapseMultiplier = Double(m.float(14) ?? 0)
            c.intervalMultiplier = Double(m.float(15) ?? 1)
            c.maximumReviewInterval = Int(m.uint(16) ?? 36500)
            c.minimumLapseInterval = Int(m.uint(17) ?? 1)
            c.graduatingIntervalGood = Int(m.uint(18) ?? 1)
            c.graduatingIntervalEasy = Int(m.uint(19) ?? 4)
            c.leechAction = DeckConfig.LeechAction(rawValue: Int(m.uint(21) ?? 0)) ?? .suspend
            c.leechThreshold = Int(m.uint(22) ?? 8)
            c.disableAutoplay = m.bool(23) ?? false
            c.capAnswerTimeToSecs = Int(m.uint(24) ?? 60)
            c.skipQuestionWhenReplayingAnswer = m.bool(26) ?? false
            c.buryNew = m.bool(27) ?? false
            c.buryReviews = m.bool(28) ?? false
            c.buryInterdayLearning = m.bool(29) ?? false
            c.newMix = DeckConfig.NewMix(rawValue: Int(m.uint(30) ?? 0)) ?? .mixWithReviews
            c.desiredRetention = Double(m.float(37) ?? 0.9)
            for field in [6, 5, 3] {
                let p = m.floats(field)
                if !p.isEmpty { c.fsrsParams = p.map(Double.init); break }
            }
            deckConfigs[id] = c
        }
    }

    // MARK: - Helpers

    static func int(_ any: Any?) -> Int? {
        switch any {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Double(s).map { Int($0) }
        default: return nil
        }
    }

    static func int64(_ any: Any?) -> Int64 {
        switch any {
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s) ?? 0
        default: return 0
        }
    }

    static func double(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    public func configValue(_ key: String) -> Any? { config[key] }

    public var rolloverHour: Int { Self.int(config["rollover"]).map { max(0, min(23, $0)) } ?? 4 }

    /// Minutes west of UTC at collection creation time, if recorded.
    public var creationOffset: Int? { Self.int(config["creationOffset"]) }

    /// Seconds a learning card may be shown ahead of its due time when nothing else is due.
    public var learnAheadSeconds: Int { Self.int(config["collapseTime"]) ?? 1200 }

    public var schedulerVersion: Int { Self.int(config["schedVer"]) ?? (usesSeparateTables ? 2 : 1) }

    /// Set by the app to force FSRS on/off (an .apkg doesn't carry the collection-wide FSRS switch).
    public var fsrsOverride: Bool?

    public var fsrsEnabled: Bool { fsrsOverride ?? (config["fsrs"] as? Bool) ?? false }

    public func deckConfig(for deckId: Int64) -> DeckConfig {
        guard let deck = decks[deckId] else { return deckConfigs[1] ?? .default }
        return deckConfigs[deck.configId] ?? deckConfigs[1] ?? .default
    }

    public func deckName(_ id: Int64) -> String { decks[id]?.name ?? "Default" }

    // MARK: - Notes & cards

    public func note(id: Int64) throws -> Note? {
        try db.query("SELECT id, guid, mid, mod, tags, flds FROM notes WHERE id = ?", [id]).first.map(Self.note(from:))
    }

    static func note(from row: SQLRow) -> Note {
        Note(id: row["id"].int64, guid: row["guid"].string, notetypeId: row["mid"].int64, mod: row["mod"].int64,
             tags: Note.splitTags(row["tags"].string), fields: Note.splitFields(row["flds"].string))
    }

    static let cardColumns = "id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data"

    static func card(from row: SQLRow) -> Card {
        Card(id: row[0].int64, noteId: row[1].int64, deckId: row[2].int64, ord: row[3].int, mod: row[4].int64,
             usn: row[5].int, type: row[6].int, queue: row[7].int, due: row[8].int64, interval: row[9].int,
             factor: row[10].int, reps: row[11].int, lapses: row[12].int, left: row[13].int,
             originalDue: row[14].int64, originalDeckId: row[15].int64, flags: row[16].int, data: row[17].string)
    }

    public func card(id: Int64) throws -> Card? {
        try db.query("SELECT \(Self.cardColumns) FROM cards WHERE id = ?", [id]).first.map(Self.card(from:))
    }

    public func cards(where clause: String, _ args: [SQLBindable] = []) throws -> [Card] {
        try db.query("SELECT \(Self.cardColumns) FROM cards WHERE \(clause)", args).map(Self.card(from:))
    }

    public func allCardIds() throws -> [Int64] {
        try db.query("SELECT id FROM cards ORDER BY id").map { $0[0].int64 }
    }

    public func update(card: Card) throws {
        try db.run("""
            UPDATE cards SET did=?, mod=?, usn=?, type=?, queue=?, due=?, ivl=?, factor=?, reps=?, lapses=?,
            left=?, odue=?, odid=?, flags=?, data=? WHERE id=?
            """, [card.deckId, card.mod, card.usn, card.type, card.queue, card.due, card.interval, card.factor,
                  card.reps, card.lapses, card.left, card.originalDue, card.originalDeckId, card.flags, card.data, card.id])
    }

    public func insert(revlog r: RevlogEntry) throws {
        var id = r.id
        // revlog ids must be unique; bump on collision like Anki does.
        while (try db.scalar("SELECT 1 FROM revlog WHERE id = ?", [id])) != .null { id += 1 }
        try db.run("INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type) VALUES (?,?,?,?,?,?,?,?,?)",
                   [id, r.cardId, r.usn, r.ease, r.interval, r.lastInterval, r.factor, r.time, r.type])
    }

    /// Remembers revlog entries removed by undo, so the removal can be synced to other devices.
    public func recordDeletedRevlog(_ id: Int64) throws {
        try db.execute("CREATE TABLE IF NOT EXISTS negoto_deleted_revlog (id INTEGER PRIMARY KEY)")
        try db.run("INSERT OR IGNORE INTO negoto_deleted_revlog (id) VALUES (?)", [id])
    }

    public func update(noteTags note: Note) throws {
        let tags = note.tags.isEmpty ? "" : " " + note.tags.joined(separator: " ") + " "
        try db.run("UPDATE notes SET tags = ?, mod = ?, usn = -1 WHERE id = ?", [tags, Int64(Date().timeIntervalSince1970), note.id])
    }

    public func markModified() {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        try? db.run("UPDATE col SET mod = ?", [ms])
    }

    // MARK: - Decks

    /// All descendant deck ids of `deckId` (including itself).
    public func deckAndChildren(_ deckId: Int64) -> [Int64] {
        guard let deck = decks[deckId] else { return [deckId] }
        let prefix = deck.name + "::"
        return [deckId] + decks.values.filter { $0.name.hasPrefix(prefix) }.map(\.id)
    }

    public var sortedDecks: [Deck] {
        decks.values.sorted { lhs, rhs in
            lhs.components.lexicographicallyPrecedes(rhs.components) { a, b in
                a.localizedStandardCompare(b) == .orderedAscending
            }
        }
    }

    // MARK: - Maintenance

    /// Moves cards out of filtered decks back to their home decks (like Anki's "Empty"),
    /// so that every card can be studied through its normal deck.
    public func emptyFilteredDecks() throws {
        try db.transaction {
            try db.run("""
                UPDATE cards SET did = odid,
                  due = (CASE WHEN odue != 0 THEN odue ELSE due END),
                  queue = (CASE
                    WHEN queue < 0 THEN queue
                    WHEN type = 0 THEN 0
                    WHEN type = 2 THEN 2
                    WHEN (CASE WHEN odue != 0 THEN odue ELSE due END) > 1000000000 THEN 1
                    ELSE 3 END),
                  odid = 0, odue = 0, usn = -1
                WHERE odid != 0
                """)
        }
    }

    /// The v1 scheduler (Anki 2.0) kept relearning cards as type=review in the learning queues.
    /// Convert them the same way Anki does when upgrading to the v2/v3 scheduler.
    public func upgradeLegacyScheduling() throws {
        guard schedulerVersion < 2 else { return }
        try db.run("UPDATE cards SET type = 3 WHERE type = 2 AND queue IN (1, 3)")
    }

    /// Unburies cards at the start of a new day, as Anki does.
    public func unburyCards() throws {
        try db.run("""
            UPDATE cards SET queue = (CASE
                WHEN type = 0 THEN 0 WHEN type = 2 THEN 2
                WHEN due > 1000000000 THEN 1 ELSE 3 END), usn = -1
            WHERE queue IN (-2, -3)
            """)
    }
}
