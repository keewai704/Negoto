import Foundation

/// Synchronises the collection through a shared folder (an iCloud container or an iCloud Drive folder).
///
/// Layout of the shared folder:
///
///     main/info.json                 version of the shared base collection
///     main/collection.anki2          shared base collection (re-uploaded after imports/deck deletions)
///     main/media/…                   media files
///     main/changes/<device>.json     study progress and option changes made on each device
///
/// Every device only writes its own change file, so files never conflict. Card states, deck options
/// and decks are merged "newest change wins"; review logs are merged as a union, and reviews removed
/// with Undo are propagated. Structural changes (imports, deleted decks) upload a new base; a device
/// that receives a newer base re-applies every change file and replays its own pending operations.
public final class SyncEngine: @unchecked Sendable {
    public let library: Library
    public let remoteRoot: URL
    public let deviceID: String
    public let deviceName: String
    let fs: SyncFileSystem

    public init(library: Library, remoteRoot: URL, deviceID: String, deviceName: String, fs: SyncFileSystem = PlainFileSystem()) {
        self.library = library
        self.remoteRoot = remoteRoot
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.fs = fs
    }

    public struct Report: Sendable {
        public var uploadedBase = false
        public var downloadedBase = false
        public var exportedCards = 0
        public var appliedCards = 0
        public var appliedReviews = 0
        public var appliedSettings = 0
        public var errors: [String] = []

        public var changedLocalData: Bool { downloadedBase || appliedCards > 0 || appliedReviews > 0 || appliedSettings > 0 }
    }

    struct RemoteInfo: Codable {
        var version: Int
        var uploadedAt: Date
        var uploadedBy: String
    }

    struct LocalState: Codable {
        var baseVersion: Int?
        var seen: [String: Int] = [:]
    }

    var mainDir: URL { remoteRoot.appendingPathComponent("main", isDirectory: true) }
    var changesDir: URL { mainDir.appendingPathComponent("changes", isDirectory: true) }
    var remoteMedia: URL { mainDir.appendingPathComponent("media", isDirectory: true) }
    var infoURL: URL { mainDir.appendingPathComponent("info.json") }
    var baseURL: URL { mainDir.appendingPathComponent(PackageImporter.collectionFileName) }
    /// Per shared folder, so switching between the iCloud container and a chosen folder starts cleanly.
    var stateURL: URL {
        let key = SHA1.hex(remoteRoot.standardizedFileURL.path).prefix(12)
        return library.mainFolder.appendingPathComponent("sync-state-\(key).json")
    }

    // MARK: - Sync

    public func sync(progress: ((String) -> Void)? = nil) throws -> Report {
        try library.prepare()
        var report = Report()
        try fs.createDirectory(changesDir)
        try fs.createDirectory(remoteMedia)
        let col = try library.openMain()
        defer { col.db.close() }
        var state = (try? Self.decoder.decode(LocalState.self, from: Data(contentsOf: stateURL))) ?? LocalState()

        if state.baseVersion != nil { report.exportedCards += try exportChanges(col) }

        for _ in 0..<3 {
            guard let remote = readRemoteInfo() else {
                // Nobody has uploaded yet: this device's collection becomes the shared base.
                progress?("upload")
                try syncMedia()
                try uploadBase(col, version: 1)
                state.baseVersion = 1
                library.clearPending()
                report.uploadedBase = true
                break
            }
            if state.baseVersion != remote.version {
                progress?("download")
                if state.baseVersion == nil {
                    // Joining an existing sync with decks of our own: merge them into the shared collection.
                    if col.noteCount > 0 { try library.snapshotMainAsPending(col) } else { library.clearPending() }
                } else if state.baseVersion != nil {
                    report.exportedCards += try exportChanges(col)
                }
                try syncMedia()
                try downloadBase(into: col)
                state.seen = [:]
                let applied = try applyChanges(col, state: &state, includeOwn: true)
                report.appliedCards += applied.cards
                report.appliedReviews += applied.reviews
                report.appliedSettings += applied.settings
                try library.replayPending(on: col)
                state.baseVersion = remote.version
                report.downloadedBase = true
            } else {
                let applied = try applyChanges(col, state: &state, includeOwn: false)
                report.appliedCards += applied.cards
                report.appliedReviews += applied.reviews
                report.appliedSettings += applied.settings
                try syncMedia()
            }
            try save(state)

            guard !library.pendingOperations().isEmpty else { break }
            // Local imports/deletions: publish a new base, unless someone else just did.
            guard readRemoteInfo()?.version == state.baseVersion else { continue }
            progress?("upload")
            report.exportedCards += try exportChanges(col)
            try syncMedia()
            let next = (state.baseVersion ?? 0) + 1
            try uploadBase(col, version: next)
            state.baseVersion = next
            library.clearPending()
            report.uploadedBase = true
            break
        }
        try save(state)
        return report
    }

    private func save(_ state: LocalState) throws {
        try Self.encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func readRemoteInfo() -> RemoteInfo? {
        guard fs.exists(infoURL), fs.exists(baseURL), let data = try? fs.read(infoURL) else { return nil }
        return try? Self.decoder.decode(RemoteInfo.self, from: data)
    }

    private func uploadBase(_ col: AnkiCollection, version: Int) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-base-\(UUID().uuidString).anki2")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try col.db.execute("VACUUM INTO '\(tmp.path.replacingOccurrences(of: "'", with: "''"))'")
        try fs.copy(from: tmp, to: baseURL)
        // info.json last: other devices only download a complete base.
        try fs.write(try Self.encoder.encode(RemoteInfo(version: version, uploadedAt: Date(), uploadedBy: deviceName)), to: infoURL)
    }

    private func downloadBase(into col: AnkiCollection) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-base-\(UUID().uuidString).anki2")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.copy(from: baseURL, to: tmp)
        try col.replaceContents(withCollectionAt: tmp)
    }

    private func syncMedia() throws {
        let local = library.mainMediaFolder
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let localNames = Set(((try? FileManager.default.contentsOfDirectory(atPath: local.path)) ?? []).filter { !$0.hasPrefix(".") })
        let remoteNames = Set(try fs.list(remoteMedia))
        for name in localNames.subtracting(remoteNames) {
            try fs.copy(from: local.appendingPathComponent(name), to: remoteMedia.appendingPathComponent(name))
        }
        for name in remoteNames.subtracting(localNames) {
            try fs.copy(from: remoteMedia.appendingPathComponent(name), to: local.appendingPathComponent(name))
        }
    }

    // MARK: - Change files

    struct SyncedCard: Codable, Equatable {
        var did: Int64, mod: Int64, type: Int, queue: Int, due: Int64, ivl: Int, factor: Int
        var reps: Int, lapses: Int, left: Int, odue: Int64, odid: Int64, flags: Int, data: String
        /// Note and template of the card, so cards added on another device can be created.
        var nid: Int64? = nil
        var ord: Int? = nil
    }

    struct SyncedReview: Codable, Equatable {
        var cid: Int64, ease: Int, ivl: Int, lastIvl: Int, factor: Int, time: Int, type: Int
    }

    struct SyncedNote: Codable, Equatable {
        var tags: String
        var mod: Int64
        /// Full content (added or edited notes). Older change files only carry tags.
        var guid: String? = nil
        var mid: Int64? = nil
        var flds: String? = nil
        var sfld: String? = nil
        var csum: Int64? = nil
    }

    /// A JSON object from the col table (deck options, deck, collection config) with its modification time.
    struct SyncedJSON: Codable, Equatable {
        var json: String
        var mod: Int64
    }

    struct DeviceChanges: Codable {
        var device: String
        var deviceName: String
        var revision: Int
        var updatedAt: Date
        var cards: [String: SyncedCard] = [:]
        var reviews: [String: SyncedReview] = [:]
        var deletedReviews: [Int64] = []
        var notes: [String: SyncedNote] = [:]
        var deckConfigs: [String: SyncedJSON]? = nil
        var decks: [String: SyncedJSON]? = nil
        var config: SyncedJSON? = nil
        var deletedNotes: [Int64]? = nil
        var deletedDecks: [Int64]? = nil
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func changeFile(device: String) -> URL { changesDir.appendingPathComponent("\(device).json") }

    static func jsonString(_ obj: [String: Any]) -> String {
        var o = obj
        o["usn"] = 0
        o["negotoUsn"] = nil
        return AnkiCollection.jsonString(o)
    }

    private static func jsonObject(_ s: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]
    }

    /// Writes local, not yet synced changes (usn = -1) into this device's change file.
    func exportChanges(_ col: AnkiCollection) throws -> Int {
        let db = col.db
        let cards = try db.query("SELECT \(AnkiCollection.cardColumns) FROM cards WHERE usn = -1").map(AnkiCollection.card(from:))
        let reviews = try db.query("SELECT id, cid, ease, ivl, lastIvl, factor, time, type FROM revlog WHERE usn = -1")
        let notes = try db.query("SELECT id, tags, mod, guid, mid, flds, sfld, csum FROM notes WHERE usn = -1")
        let deleted = db.tableExists("negoto_deleted_revlog")
            ? try db.query("SELECT id FROM negoto_deleted_revlog").map { $0[0].int64 } : []
        let deletedNotes = db.tableExists("negoto_deleted_notes")
            ? try db.query("SELECT id FROM negoto_deleted_notes").map { $0[0].int64 } : []
        let deletedDecks = db.tableExists("negoto_deleted_decks")
            ? try db.query("SELECT id FROM negoto_deleted_decks").map { $0[0].int64 } : []
        var dconf = try col.colJSON("dconf"), decks = try col.colJSON("decks"), conf = try col.colJSON("conf")
        let changedConfigs = dconf.filter { (($0.value as? [String: Any])?["usn"] as? NSNumber)?.intValue == -1 }
        let changedDecks = decks.filter { (($0.value as? [String: Any])?["usn"] as? NSNumber)?.intValue == -1 }
        let confChanged = (conf["negotoUsn"] as? NSNumber)?.intValue == -1
        if cards.isEmpty && reviews.isEmpty && notes.isEmpty && deleted.isEmpty && changedConfigs.isEmpty
            && changedDecks.isEmpty && !confChanged && deletedNotes.isEmpty && deletedDecks.isEmpty { return 0 }

        let file = changeFile(device: deviceID)
        var changes = (try? Self.decoder.decode(DeviceChanges.self, from: fs.read(file)))
            ?? DeviceChanges(device: deviceID, deviceName: deviceName, revision: 0, updatedAt: Date())
        for c in cards {
            changes.cards[String(c.id)] = SyncedCard(
                did: c.deckId, mod: c.mod, type: c.type, queue: c.queue, due: c.due, ivl: c.interval, factor: c.factor,
                reps: c.reps, lapses: c.lapses, left: c.left, odue: c.originalDue, odid: c.originalDeckId, flags: c.flags, data: c.data,
                nid: c.noteId, ord: c.ord)
        }
        for r in reviews {
            changes.reviews[String(r[0].int64)] = SyncedReview(
                cid: r[1].int64, ease: r[2].int, ivl: r[3].int, lastIvl: r[4].int, factor: r[5].int, time: r[6].int, type: r[7].int)
        }
        for n in notes {
            changes.notes[String(n[0].int64)] = SyncedNote(tags: n[1].string, mod: n[2].int64, guid: n[3].string, mid: n[4].int64,
                                                           flds: n[5].string, sfld: n[6].string, csum: n[7].int64)
        }
        for id in deletedNotes {
            changes.notes[String(id)] = nil
            if !(changes.deletedNotes ?? []).contains(id) { changes.deletedNotes = (changes.deletedNotes ?? []) + [id] }
        }
        for id in deletedDecks where !(changes.deletedDecks ?? []).contains(id) {
            changes.deletedDecks = (changes.deletedDecks ?? []) + [id]
            changes.decks?[String(id)] = nil
        }
        for id in deleted {
            changes.reviews[String(id)] = nil
            if !changes.deletedReviews.contains(id) { changes.deletedReviews.append(id) }
        }
        func synced(_ value: Any) -> SyncedJSON {
            var d = value as? [String: Any] ?? [:]
            d["usn"] = 0
            return SyncedJSON(json: AnkiCollection.jsonString(d), mod: AnkiCollection.int64(d["mod"]))
        }
        for (key, value) in changedConfigs { changes.deckConfigs = (changes.deckConfigs ?? [:]).merging([key: synced(value)]) { $1 } }
        for (key, value) in changedDecks { changes.decks = (changes.decks ?? [:]).merging([key: synced(value)]) { $1 } }
        if confChanged {
            var c = conf
            c["negotoUsn"] = 0
            changes.config = SyncedJSON(json: AnkiCollection.jsonString(c), mod: AnkiCollection.int64(c["negotoMod"]))
        }
        changes.deviceName = deviceName
        changes.revision += 1
        changes.updatedAt = Date()
        try fs.write(try Self.encoder.encode(changes), to: file)

        // Mark as synced, unless the row changed again in the meantime.
        try db.transaction {
            for c in cards { try db.run("UPDATE cards SET usn = 0 WHERE id = ? AND usn = -1 AND mod = ?", [c.id, c.mod]) }
            for r in reviews { try db.run("UPDATE revlog SET usn = 0 WHERE id = ?", [r[0].int64]) }
            for n in notes { try db.run("UPDATE notes SET usn = 0 WHERE id = ? AND usn = -1 AND mod = ?", [n[0].int64, n[2].int64]) }
            for id in deleted { try db.run("DELETE FROM negoto_deleted_revlog WHERE id = ?", [id]) }
            for id in deletedNotes { try db.run("DELETE FROM negoto_deleted_notes WHERE id = ?", [id]) }
            for id in deletedDecks { try db.run("DELETE FROM negoto_deleted_decks WHERE id = ?", [id]) }
            if !changedConfigs.isEmpty {
                for key in changedConfigs.keys { if var d = dconf[key] as? [String: Any] { d["usn"] = 0; dconf[key] = d } }
                try col.setColJSON("dconf", dconf)
            }
            if !changedDecks.isEmpty {
                for key in changedDecks.keys { if var d = decks[key] as? [String: Any] { d["usn"] = 0; decks[key] = d } }
                try col.setColJSON("decks", decks)
            }
            if confChanged {
                conf["negotoUsn"] = 0
                try col.setColJSON("conf", conf)
            }
        }
        return cards.count
    }

    /// Applies change files (other devices', and our own after a new base was downloaded).
    func applyChanges(_ col: AnkiCollection, state: inout LocalState, includeOwn: Bool)
        throws -> (cards: Int, reviews: Int, settings: Int) {
        let db = col.db
        var appliedCards = 0, appliedReviews = 0, appliedSettings = 0
        // Decks deleted on any device must not come back from another device's change file.
        var deletedDecks = Set<Int64>(), deletedNotes = Set<Int64>()
        var files: [(device: String, changes: DeviceChanges)] = []
        for name in try fs.list(changesDir) where name.hasSuffix(".json") {
            guard let changes = try? Self.decoder.decode(DeviceChanges.self, from: fs.read(changesDir.appendingPathComponent(name))) else {
                continue  // partially written or unreadable; retried next time
            }
            deletedDecks.formUnion(changes.deletedDecks ?? [])
            deletedNotes.formUnion(changes.deletedNotes ?? [])
            files.append((String(name.dropLast(5)), changes))
        }
        for (device, changes) in files {
            if device == deviceID && !includeOwn { continue }
            if let seen = state.seen[device], seen >= changes.revision { continue }
            try db.transaction {
                // Decks first (new cards may live in a deck created on the other device), then notes, then cards.
                for (column, entries) in [("dconf", changes.deckConfigs ?? [:]), ("decks", changes.decks ?? [:])] where !entries.isEmpty {
                    var all = try col.colJSON(column)
                    var changed = false
                    for (key, entry) in entries {
                        guard let obj = Self.jsonObject(entry.json) else { continue }
                        if column == "decks", (all[key] as? [String: Any]) == nil {
                            // A deck created on another device: add it unless it was deleted somewhere.
                            guard let id = Int64(key), !deletedDecks.contains(id) else { continue }
                            let name = obj["name"] as? String
                            if let name, all.values.contains(where: { ($0 as? [String: Any])?["name"] as? String == name }) { continue }
                        }
                        let local = all[key] as? [String: Any]
                        let localMod = AnkiCollection.int64(local?["mod"])
                        let localDirty = (local?["usn"] as? NSNumber)?.intValue == -1
                        // Mods have 1-second resolution: on a tie, a remote change beats an already-synced local value.
                        guard local == nil || entry.mod > localMod || (entry.mod == localMod && !localDirty) else { continue }
                        if let local, Self.jsonString(local) == Self.jsonString(obj) { continue }
                        all[key] = obj
                        changed = true
                        appliedSettings += 1
                    }
                    if changed { try col.setColJSON(column, all) }
                }
                for (key, n) in changes.notes {
                    guard let id = Int64(key) else { continue }
                    let local = try db.scalar("SELECT mod FROM notes WHERE id = ?", [id])
                    if local.isNull {
                        // Added on another device.
                        guard let guid = n.guid, let mid = n.mid, let flds = n.flds, col.notetypes[mid] != nil,
                              !deletedNotes.contains(id) else { continue }
                        try db.run("INSERT OR IGNORE INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) VALUES (?,?,?,?,0,?,?,?,?,0,'')",
                                   [id, guid, mid, n.mod, n.tags, flds, n.sfld ?? "", n.csum ?? 0])
                        appliedSettings += 1
                        continue
                    }
                    guard n.mod > local.int64 else { continue }
                    if let flds = n.flds {
                        try db.run("UPDATE notes SET tags = ?, flds = ?, sfld = ?, csum = ?, mod = ?, usn = 0 WHERE id = ?",
                                   [n.tags, flds, n.sfld ?? "", n.csum ?? 0, n.mod, id])
                    } else {
                        try db.run("UPDATE notes SET tags = ?, mod = ?, usn = 0 WHERE id = ?", [n.tags, n.mod, id])
                    }
                }
                for (key, c) in changes.cards {
                    guard let id = Int64(key) else { continue }
                    let local = try db.scalar("SELECT mod FROM cards WHERE id = ?", [id])
                    if local.isNull {
                        guard let nid = c.nid, let ord = c.ord, !deletedNotes.contains(nid),
                              !(try db.scalar("SELECT 1 FROM notes WHERE id = ?", [nid])).isNull else { continue }
                        try db.run("""
                            INSERT OR IGNORE INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left,
                            odue, odid, flags, data) VALUES (?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,?,?)
                            """, [id, nid, c.did, ord, c.mod, c.type, c.queue, c.due, c.ivl, c.factor, c.reps, c.lapses, c.left,
                                  c.odue, c.odid, c.flags, c.data])
                        appliedCards += 1
                        continue
                    }
                    guard c.mod > local.int64 else { continue }
                    try db.run("""
                        UPDATE cards SET did=?, mod=?, usn=0, type=?, queue=?, due=?, ivl=?, factor=?, reps=?, lapses=?,
                        left=?, odue=?, odid=?, flags=?, data=? WHERE id=?
                        """, [c.did, c.mod, c.type, c.queue, c.due, c.ivl, c.factor, c.reps, c.lapses, c.left, c.odue, c.odid,
                              c.flags, c.data, id])
                    appliedCards += 1
                }
                let deleted = Set(changes.deletedReviews)
                for (key, r) in changes.reviews {
                    guard let id = Int64(key), !deleted.contains(id) else { continue }
                    appliedReviews += try db.run("""
                        INSERT OR IGNORE INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type)
                        VALUES (?,?,0,?,?,?,?,?,?)
                        """, [id, r.cid, r.ease, r.ivl, r.lastIvl, r.factor, r.time, r.type])
                }
                for id in deleted { try db.run("DELETE FROM revlog WHERE id = ?", [id]) }
                for id in changes.deletedNotes ?? [] {
                    try db.run("DELETE FROM cards WHERE nid = ?", [id])
                    try db.run("DELETE FROM notes WHERE id = ?", [id])
                }
                if let entry = changes.config, let obj = Self.jsonObject(entry.json) {
                    let conf = try col.colJSON("conf")
                    let localMod = AnkiCollection.int64(conf["negotoMod"])
                    let localDirty = (conf["negotoUsn"] as? NSNumber)?.intValue == -1
                    if (entry.mod > localMod || (entry.mod == localMod && !localDirty)),
                       Self.jsonString(conf) != Self.jsonString(obj) {
                        try col.setColJSON("conf", obj)
                        appliedSettings += 1
                    }
                }
            }
            state.seen[device] = changes.revision
        }
        if appliedSettings > 0 { try col.reload() }
        return (appliedCards, appliedReviews, appliedSettings)
    }
}
