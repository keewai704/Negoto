import Foundation

/// Writing support for Negoto's own collection, which always uses Anki's schema 11
/// (note types, decks and deck options stored as JSON in the `col` table).
extension AnkiCollection {
    /// A fixed creation time so that day numbers agree on every device that shares the collection.
    public static let canonicalCreationTime: Int64 = 1_577_851_200  // 2020-01-01 04:00 UTC

    static let schema11 = """
        CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null,
          ver integer not null, dty integer not null, usn integer not null, ls integer not null, conf text not null,
          models text not null, decks text not null, dconf text not null, tags text not null);
        CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null,
          usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null,
          flags integer not null, data text not null);
        CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null,
          mod integer not null, usn integer not null, type integer not null, queue integer not null, due integer not null,
          ivl integer not null, factor integer not null, reps integer not null, lapses integer not null,
          left integer not null, odue integer not null, odid integer not null, flags integer not null, data text not null);
        CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null, ease integer not null,
          ivl integer not null, lastIvl integer not null, factor integer not null, time integer not null, type integer not null);
        CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
        CREATE INDEX ix_notes_usn on notes (usn);
        CREATE INDEX ix_cards_usn on cards (usn);
        CREATE INDEX ix_revlog_usn on revlog (usn);
        CREATE INDEX ix_cards_nid on cards (nid);
        CREATE INDEX ix_cards_sched on cards (did, queue, due);
        CREATE INDEX ix_revlog_cid on revlog (cid);
        CREATE INDEX ix_notes_csum on notes (csum);
        """

    /// Creates an empty collection with a "Default" deck and default options.
    public static func createEmpty(at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let db = try SQLiteDatabase(path: url.path)
        defer { db.close() }
        try db.execute(schema11)
        let now = Int64(Date().timeIntervalSince1970)
        let conf: [String: Any] = ["schedVer": 2, "rollover": 4, "collapseTime": 1200, "nextPos": 1, "curDeck": 1,
                                   "fsrs": false, "negotoMod": now]
        var defaultDeck = deckJSON(Deck(id: 1, name: "Default", configId: 1, isFiltered: false, description: ""), mod: now)
        defaultDeck["usn"] = 0
        let decks: [String: Any] = ["1": defaultDeck]
        var dconf = deckConfigJSON(DeckConfig.default, mod: now)
        dconf["usn"] = 0
        try db.run("INSERT INTO col VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, '{}', ?, ?, '{}')",
                   [canonicalCreationTime, now * 1000, now * 1000, jsonString(conf), jsonString(decks), jsonString(["1": dconf])])
    }

    // MARK: JSON helpers

    static func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    func colJSON(_ column: String) throws -> [String: Any] {
        let s = try db.scalar("SELECT \(column) FROM col").string
        return (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
    }

    func setColJSON(_ column: String, _ dict: [String: Any]) throws {
        try db.run("UPDATE col SET \(column) = ?, mod = ?", [Self.jsonString(dict), Int64(Date().timeIntervalSince1970 * 1000)])
    }

    static func notetypeJSON(_ nt: Notetype, mod: Int64) -> [String: Any] {
        [
            "id": nt.id, "name": nt.name, "type": nt.kind.rawValue, "css": nt.css, "mod": mod, "usn": 0,
            "sortf": nt.sortFieldIndex, "latexPre": nt.latexPre, "latexPost": nt.latexPost, "latexsvg": nt.latexSvg,
            "did": 1, "tags": [String](), "vers": [String](), "req": [Any](),
            "flds": nt.fields.sorted { $0.ord < $1.ord }.enumerated().map { i, f in
                ["name": f.name, "ord": i, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": [String]()] as [String: Any]
            },
            "tmpls": nt.templates.sorted { $0.ord < $1.ord }.enumerated().map { i, t in
                ["name": t.name, "ord": i, "qfmt": t.questionFormat, "afmt": t.answerFormat, "bqfmt": "", "bafmt": "",
                 "did": NSNull()] as [String: Any]
            },
        ]
    }

    static func deckJSON(_ deck: Deck, mod: Int64) -> [String: Any] {
        var d: [String: Any] = [
            "id": deck.id, "name": deck.name, "conf": deck.configId, "dyn": 0, "desc": deck.description, "mod": mod,
            "usn": -1, "collapsed": false, "browserCollapsed": false, "newToday": [0, 0], "revToday": [0, 0],
            "lrnToday": [0, 0], "timeToday": [0, 0], "extendNew": 0, "extendRev": 0,
        ]
        if let n = deck.newLimit { d["newLimit"] = n }
        if let r = deck.reviewLimit { d["reviewLimit"] = r }
        return d
    }

    static func deckConfigJSON(_ c: DeckConfig, mod: Int64) -> [String: Any] {
        var d: [String: Any] = [
            "id": c.id, "name": c.name, "mod": mod, "usn": -1, "dyn": false, "maxTaken": c.capAnswerTimeToSecs,
            "autoplay": !c.disableAutoplay, "replayq": !c.skipQuestionWhenReplayingAnswer, "timer": 0,
            "newMix": c.newMix.rawValue, "buryInterdayLearning": c.buryInterdayLearning,
            "desiredRetention": c.desiredRetention,
            "new": ["delays": c.learnSteps, "ints": [c.graduatingIntervalGood, c.graduatingIntervalEasy, 0],
                    "initialFactor": Int((c.initialEase * 1000).rounded()), "perDay": c.newPerDay, "order": 1,
                    "bury": c.buryNew] as [String: Any],
            "rev": ["perDay": c.reviewsPerDay, "ease4": c.easyMultiplier, "ivlFct": c.intervalMultiplier,
                    "maxIvl": c.maximumReviewInterval, "hardFactor": c.hardMultiplier, "bury": c.buryReviews,
                    "fuzz": 0.05, "minSpace": 1] as [String: Any],
            "lapse": ["delays": c.relearnSteps, "mult": c.lapseMultiplier, "minInt": c.minimumLapseInterval,
                      "leechFails": c.leechThreshold, "leechAction": c.leechAction.rawValue] as [String: Any],
        ]
        switch c.fsrsParams.count {
        case 21: d["fsrsParams6"] = c.fsrsParams
        case 19: d["fsrsParams5"] = c.fsrsParams
        case 17: d["fsrsWeights"] = c.fsrsParams
        default: break
        }
        return d
    }

    // MARK: Editing (schema 11 collections)

    private var nowSecs: Int64 { Int64(Date().timeIntervalSince1970) }

    /// Saves deck options. Marked as a local change so it is synced.
    public func save(deckConfig: DeckConfig) throws {
        var all = try colJSON("dconf")
        all[String(deckConfig.id)] = Self.deckConfigJSON(deckConfig, mod: nowSecs)
        try setColJSON("dconf", all)
        try reload()
    }

    /// Creates a new options preset (a copy of `base`) and returns it.
    public func addDeckConfig(copying base: DeckConfig, name: String) throws -> DeckConfig {
        let all = try colJSON("dconf")
        let maxID = all.keys.compactMap(Int64.init).max() ?? 1
        var conf = base
        conf.id = max(maxID + 1, nowSecs * 1000)
        conf.name = name
        try save(deckConfig: conf)
        return conf
    }

    private func updateDeck(_ id: Int64, _ change: (inout [String: Any]) -> Void) throws {
        var all = try colJSON("decks")
        guard var d = all[String(id)] as? [String: Any] else { return }
        change(&d)
        d["mod"] = nowSecs
        d["usn"] = -1
        all[String(id)] = d
        try setColJSON("decks", all)
    }

    public func setDeckConfigID(deck id: Int64, configID: Int64) throws {
        try updateDeck(id) { $0["conf"] = configID }
        try reload()
    }

    /// Per-deck daily limits overriding the preset (nil = use the preset).
    public func setDeckLimits(deck id: Int64, newLimit: Int?, reviewLimit: Int?) throws {
        try updateDeck(id) { d in
            if let n = newLimit { d["newLimit"] = n } else { d.removeValue(forKey: "newLimit") }
            if let r = reviewLimit { d["reviewLimit"] = r } else { d.removeValue(forKey: "reviewLimit") }
        }
        try reload()
    }

    /// Custom study: lets today's limits of a deck grow by the given numbers of cards (added to any
    /// earlier extension made today).
    public func extendTodayLimits(deck id: Int64, new extraNew: Int, review extraReview: Int) throws {
        let today = timingToday().daysElapsed
        try updateDeck(id) { d in
            let old = d["negotoExtend"] as? [String: Any]
            let sameDay = Self.int(old?["day"]) == today
            let n = (sameDay ? Self.int(old?["new"]) ?? 0 : 0) + max(0, extraNew)
            let r = (sameDay ? Self.int(old?["rev"]) ?? 0 : 0) + max(0, extraReview)
            d["negotoExtend"] = ["day": today, "new": n, "rev": r]
        }
        try reload()
    }

    /// Decks using the given options preset.
    public func decks(usingConfig configID: Int64) -> [Deck] {
        decks.values.filter { !$0.isFiltered && $0.configId == configID }.sorted { $0.name < $1.name }
    }

    public func setFSRS(_ enabled: Bool) throws {
        var conf = try colJSON("conf")
        conf["fsrs"] = enabled
        conf["negotoMod"] = nowSecs
        conf["negotoUsn"] = -1
        try setColJSON("conf", conf)
        try reload()
    }

    /// Renames a deck and its subdecks.
    public func renameDeck(_ id: Int64, to newName: String) throws {
        guard let deck = decks[id] else { return }
        let cleaned = newName.components(separatedBy: "::").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "::")
        guard !cleaned.isEmpty, cleaned != deck.name else { return }
        var all = try colJSON("decks")
        let oldPrefix = deck.name + "::"
        for (key, value) in all {
            guard var d = value as? [String: Any], let name = d["name"] as? String else { continue }
            if name == deck.name {
                d["name"] = cleaned
            } else if name.hasPrefix(oldPrefix) {
                d["name"] = cleaned + "::" + name.dropFirst(oldPrefix.count)
            } else { continue }
            d["mod"] = nowSecs
            d["usn"] = -1
            all[key] = d
        }
        try setColJSON("decks", all)
        try ensureParents(of: cleaned)
        try reload()
    }

    /// Returns the id of the deck with this name, creating it (and its parents) if needed.
    @discardableResult
    public func findOrCreateDeck(named name: String, configID: Int64 = 1) throws -> Int64 {
        if let existing = decks.values.first(where: { $0.name == name }) { return existing.id }
        var all = try colJSON("decks")
        let existingByName = Dictionary(all.values.compactMap { $0 as? [String: Any] }.compactMap { d -> (String, Int64)? in
            guard let n = d["name"] as? String else { return nil }
            return (n, Self.int64(d["id"]))
        }, uniquingKeysWith: { a, _ in a })
        if let id = existingByName[name] { return id }
        var id = max((all.keys.compactMap(Int64.init).max() ?? 1) + 1, nowSecs * 1000)
        while all[String(id)] != nil { id += 1 }
        all[String(id)] = Self.deckJSON(Deck(id: id, name: name, configId: configID, isFiltered: false, description: ""), mod: nowSecs)
        try setColJSON("decks", all)
        try reload()
        try ensureParents(of: name)
        return id
    }

    private func ensureParents(of name: String) throws {
        let parts = name.components(separatedBy: "::")
        guard parts.count > 1 else { return }
        for i in 1..<parts.count {
            let parent = parts[0..<i].joined(separator: "::")
            if !decks.values.contains(where: { $0.name == parent }) { try findOrCreateDeck(named: parent) }
        }
    }

    /// Deletes a deck, its subdecks and their cards (notes left without cards are removed too).
    public func deleteDeck(_ id: Int64) throws {
        let ids = deckAndChildren(id)
        let list = "(" + ids.map(String.init).joined(separator: ",") + ")"
        try db.execute("CREATE TABLE IF NOT EXISTS negoto_deleted_decks (id INTEGER PRIMARY KEY)")
        try db.transaction {
            for d in ids where d != 1 { try db.run("INSERT OR IGNORE INTO negoto_deleted_decks (id) VALUES (?)", [d]) }
            try db.run("DELETE FROM cards WHERE did IN \(list)")
            try db.run("DELETE FROM notes WHERE id NOT IN (SELECT DISTINCT nid FROM cards)")
            var all = try colJSON("decks")
            for d in ids where d != 1 { all.removeValue(forKey: String(d)) }
            try setColJSON("decks", all)
        }
        try reload()
    }

    public var noteCount: Int { (try? db.scalar("SELECT count() FROM notes").int) ?? 0 }
    public var cardCount: Int { (try? db.scalar("SELECT count() FROM cards").int) ?? 0 }
}
