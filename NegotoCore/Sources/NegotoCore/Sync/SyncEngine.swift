import Foundation

/// Synchronises the library through a shared folder (e.g. in iCloud Drive).
///
/// Layout of the shared folder:
///
///     collections/<uuid>/info.json            collection metadata (name, scheduler choice)
///     collections/<uuid>/collection.anki2     base snapshot, uploaded once
///     collections/<uuid>/media/…              media files
///     collections/<uuid>/changes/<device>.json study progress made on each device
///     deleted.json                            collections deleted by the user
///
/// Every device only ever writes its own `changes/<device>.json`, so files never conflict.
/// Card states are merged "newest change wins" (by the card's modification time), review logs
/// are merged as a union, and reviews removed with Undo are propagated as deletions.
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
        public var uploaded: [UUID] = []
        public var downloaded: [UUID] = []
        /// Collections deleted on another device; the app should remove them locally.
        public var deletedRemotely: [UUID] = []
        public var infoUpdated: [UUID] = []
        public var exportedCards = 0
        public var appliedCards = 0
        public var appliedReviews = 0
        public var errors: [String] = []

        public var changedLocalData: Bool {
            !downloaded.isEmpty || !deletedRemotely.isEmpty || !infoUpdated.isEmpty || appliedCards > 0 || appliedReviews > 0
        }
    }

    var collectionsDir: URL { remoteRoot.appendingPathComponent("collections", isDirectory: true) }
    func remoteDir(_ id: UUID) -> URL { collectionsDir.appendingPathComponent(id.uuidString, isDirectory: true) }
    var tombstoneFile: URL { remoteRoot.appendingPathComponent("deleted.json") }

    // MARK: - Entry points

    public func sync(progress: ((String) -> Void)? = nil) throws -> Report {
        var report = Report()
        try fs.createDirectory(collectionsDir)
        let tombstones = readTombstones()
        let remoteIDs = Set(try fs.list(collectionsDir).compactMap(UUID.init(uuidString:)))
        let locals = library.list()

        for info in locals {
            if tombstones[info.id.uuidString] != nil {
                report.deletedRemotely.append(info.id)
                continue
            }
            progress?(info.name)
            do {
                try syncCollection(info, report: &report)
            } catch {
                report.errors.append("\(info.name): \(error.localizedDescription)")
            }
        }
        let localIDs = Set(locals.map(\.id))
        for id in remoteIDs.subtracting(localIDs) where tombstones[id.uuidString] == nil {
            do {
                if let name = try download(id, report: &report) { progress?(name) }
            } catch {
                try? FileManager.default.removeItem(at: library.folder(for: id))
                report.errors.append("\(id.uuidString): \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Records that the user deleted a collection, so other devices delete it too.
    public func markDeleted(_ id: UUID) throws {
        var tombstones = readTombstones()
        tombstones[id.uuidString] = Date()
        try fs.write(try Self.encoder.encode(tombstones), to: tombstoneFile)
        try fs.remove(remoteDir(id))
    }

    // MARK: - Per collection

    private func syncCollection(_ info: CollectionInfo, report: inout Report) throws {
        let dir = remoteDir(info.id)
        let col = try AnkiCollection(path: library.collectionFile(for: info.id), mediaFolder: library.mediaFolder(for: info.id))
        defer { col.db.close() }

        report.exportedCards += try exportChanges(col, dir: dir)

        let remoteInfoURL = dir.appendingPathComponent("info.json")
        let baseURL = dir.appendingPathComponent(PackageImporter.collectionFileName)
        if !fs.exists(baseURL) || !fs.exists(remoteInfoURL) {
            try uploadBase(col, info: info, dir: dir)
            report.uploaded.append(info.id)
            return
        }
        // Metadata: the most recently edited side wins.
        if let remote = try? Self.decoder.decode(CollectionInfo.self, from: fs.read(remoteInfoURL)) {
            let localDate = info.modifiedAt ?? .distantPast
            let remoteDate = remote.modifiedAt ?? .distantPast
            if remoteDate > localDate {
                var updated = info
                updated.name = remote.name
                updated.useFSRS = remote.useFSRS
                updated.modifiedAt = remote.modifiedAt
                try library.save(updated)
                report.infoUpdated.append(info.id)
            } else if localDate > remoteDate {
                try fs.write(try Self.encoder.encode(sharedInfo(info)), to: remoteInfoURL)
            }
        }
        try syncMedia(local: library.mediaFolder(for: info.id), remote: dir.appendingPathComponent("media", isDirectory: true))
        let (cards, reviews) = try applyRemoteChanges(col, dir: dir, folder: library.folder(for: info.id))
        report.appliedCards += cards
        report.appliedReviews += reviews
    }

    private func sharedInfo(_ info: CollectionInfo) -> CollectionInfo {
        var shared = info
        shared.lastUnburiedDay = nil
        return shared
    }

    private func uploadBase(_ col: AnkiCollection, info: CollectionInfo, dir: URL) throws {
        try fs.createDirectory(dir)
        try fs.createDirectory(dir.appendingPathComponent("changes", isDirectory: true))
        // A consistent copy of the live database.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-snapshot-\(UUID().uuidString).anki2")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try col.db.execute("VACUUM INTO '\(tmp.path.replacingOccurrences(of: "'", with: "''"))'")
        try syncMedia(local: library.mediaFolder(for: info.id), remote: dir.appendingPathComponent("media", isDirectory: true))
        try fs.copy(from: tmp, to: dir.appendingPathComponent(PackageImporter.collectionFileName))
        // info.json last: other devices only download complete collections.
        var shared = sharedInfo(info)
        if shared.modifiedAt == nil { shared.modifiedAt = Date() }
        try fs.write(try Self.encoder.encode(shared), to: dir.appendingPathComponent("info.json"))
    }

    private func syncMedia(local: URL, remote: URL) throws {
        try fs.createDirectory(remote)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let localNames = Set(((try? FileManager.default.contentsOfDirectory(atPath: local.path)) ?? []).filter { !$0.hasPrefix(".") })
        let remoteNames = Set(try fs.list(remote))
        for name in localNames.subtracting(remoteNames) {
            try fs.copy(from: local.appendingPathComponent(name), to: remote.appendingPathComponent(name))
        }
        for name in remoteNames.subtracting(localNames) {
            try fs.copy(from: remote.appendingPathComponent(name), to: local.appendingPathComponent(name))
        }
    }

    private func download(_ id: UUID, report: inout Report) throws -> String? {
        let dir = remoteDir(id)
        let infoURL = dir.appendingPathComponent("info.json")
        let baseURL = dir.appendingPathComponent(PackageImporter.collectionFileName)
        // Still being uploaded by another device.
        guard fs.exists(infoURL), fs.exists(baseURL) else { return nil }
        var info = try Self.decoder.decode(CollectionInfo.self, from: fs.read(infoURL))
        info.id = id
        info.lastUnburiedDay = nil
        let folder = library.folder(for: id)
        try FileManager.default.createDirectory(at: library.mediaFolder(for: id), withIntermediateDirectories: true)
        try fs.copy(from: baseURL, to: library.collectionFile(for: id))
        try syncMedia(local: library.mediaFolder(for: id), remote: dir.appendingPathComponent("media", isDirectory: true))
        let col = try AnkiCollection(path: library.collectionFile(for: id), mediaFolder: library.mediaFolder(for: id))
        defer { col.db.close() }
        try col.db.transaction {
            try col.db.run("UPDATE cards SET usn = 0 WHERE usn = -1")
            try col.db.run("UPDATE revlog SET usn = 0 WHERE usn = -1")
            try col.db.run("UPDATE notes SET usn = 0 WHERE usn = -1")
        }
        let (cards, reviews) = try applyRemoteChanges(col, dir: dir, folder: folder)
        report.appliedCards += cards
        report.appliedReviews += reviews
        try library.save(info)  // saved last: an interrupted download is retried next time
        report.downloaded.append(id)
        return info.name
    }

    // MARK: - Change files

    struct SyncedCard: Codable, Equatable {
        var did: Int64, mod: Int64, type: Int, queue: Int, due: Int64, ivl: Int, factor: Int
        var reps: Int, lapses: Int, left: Int, odue: Int64, odid: Int64, flags: Int, data: String
    }

    struct SyncedReview: Codable, Equatable {
        var cid: Int64, ease: Int, ivl: Int, lastIvl: Int, factor: Int, time: Int, type: Int
    }

    struct SyncedNote: Codable, Equatable {
        var tags: String
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
    }

    struct LocalState: Codable {
        var seen: [String: Int] = [:]
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

    private func changeFile(_ dir: URL, device: String) -> URL {
        dir.appendingPathComponent("changes", isDirectory: true).appendingPathComponent("\(device).json")
    }

    /// Writes local, not yet synced changes (usn = -1) into this device's change file.
    func exportChanges(_ col: AnkiCollection, dir: URL) throws -> Int {
        let db = col.db
        let cards = try db.query("SELECT \(AnkiCollection.cardColumns) FROM cards WHERE usn = -1").map(AnkiCollection.card(from:))
        let reviews = try db.query("SELECT id, cid, ease, ivl, lastIvl, factor, time, type FROM revlog WHERE usn = -1")
        let notes = try db.query("SELECT id, tags, mod FROM notes WHERE usn = -1")
        let deleted = db.tableExists("negoto_deleted_revlog")
            ? try db.query("SELECT id FROM negoto_deleted_revlog").map { $0[0].int64 } : []
        if cards.isEmpty && reviews.isEmpty && notes.isEmpty && deleted.isEmpty { return 0 }

        try fs.createDirectory(dir.appendingPathComponent("changes", isDirectory: true))
        let file = changeFile(dir, device: deviceID)
        var changes = (try? Self.decoder.decode(DeviceChanges.self, from: fs.read(file)))
            ?? DeviceChanges(device: deviceID, deviceName: deviceName, revision: 0, updatedAt: Date())
        for c in cards {
            changes.cards[String(c.id)] = SyncedCard(
                did: c.deckId, mod: c.mod, type: c.type, queue: c.queue, due: c.due, ivl: c.interval, factor: c.factor,
                reps: c.reps, lapses: c.lapses, left: c.left, odue: c.originalDue, odid: c.originalDeckId, flags: c.flags, data: c.data)
        }
        for r in reviews {
            changes.reviews[String(r[0].int64)] = SyncedReview(
                cid: r[1].int64, ease: r[2].int, ivl: r[3].int, lastIvl: r[4].int, factor: r[5].int, time: r[6].int, type: r[7].int)
        }
        for n in notes {
            changes.notes[String(n[0].int64)] = SyncedNote(tags: n[1].string, mod: n[2].int64)
        }
        for id in deleted {
            changes.reviews[String(id)] = nil
            if !changes.deletedReviews.contains(id) { changes.deletedReviews.append(id) }
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
        }
        return cards.count
    }

    /// Applies change files written by other devices.
    func applyRemoteChanges(_ col: AnkiCollection, dir: URL, folder: URL) throws -> (cards: Int, reviews: Int) {
        let changesDir = dir.appendingPathComponent("changes", isDirectory: true)
        guard fs.exists(changesDir) else { return (0, 0) }
        let stateURL = folder.appendingPathComponent("sync-state.json")
        var state = (try? Self.decoder.decode(LocalState.self, from: Data(contentsOf: stateURL))) ?? LocalState()
        let db = col.db
        var appliedCards = 0, appliedReviews = 0
        for name in try fs.list(changesDir) where name.hasSuffix(".json") {
            let device = String(name.dropLast(5))
            guard device != deviceID else { continue }
            guard let changes = try? Self.decoder.decode(DeviceChanges.self, from: fs.read(changesDir.appendingPathComponent(name))) else {
                continue  // partially written or unreadable; retried next time
            }
            if let seen = state.seen[device], seen >= changes.revision { continue }
            try db.transaction {
                for (key, c) in changes.cards {
                    guard let id = Int64(key) else { continue }
                    let local = try db.scalar("SELECT mod FROM cards WHERE id = ?", [id])
                    guard !local.isNull, c.mod > local.int64 else { continue }
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
                for (key, n) in changes.notes {
                    guard let id = Int64(key) else { continue }
                    let local = try db.scalar("SELECT mod FROM notes WHERE id = ?", [id])
                    guard !local.isNull, n.mod > local.int64 else { continue }
                    try db.run("UPDATE notes SET tags = ?, mod = ?, usn = 0 WHERE id = ?", [n.tags, n.mod, id])
                }
            }
            state.seen[device] = changes.revision
        }
        try Self.encoder.encode(state).write(to: stateURL, options: .atomic)
        return (appliedCards, appliedReviews)
    }

    private func readTombstones() -> [String: Date] {
        guard fs.exists(tombstoneFile), let data = try? fs.read(tombstoneFile) else { return [:] }
        return (try? Self.decoder.decode([String: Date].self, from: data)) ?? [:]
    }
}
