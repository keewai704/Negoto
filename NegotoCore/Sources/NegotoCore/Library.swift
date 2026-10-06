import Foundation

/// Metadata of a collection folder (used for migrating the multi-collection layout of Negoto ≤1.0.6).
public struct CollectionInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sourceFilename: String
    public var importedAt: Date
    public var format: String
    public var noteCount: Int
    public var cardCount: Int
    public var mediaCount: Int
    public var missingMediaCount: Int
    public var useFSRS: Bool?
    public var lastUnburiedDay: Int?
    public var modifiedAt: Date?
}

/// A local change that replaces the shared base collection; it is replayed if another device
/// uploaded a new base in the meantime (see `SyncEngine`).
public struct PendingOperation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case merge, replace, deleteDeck }
    public var kind: Kind
    /// For merge/replace: file name (in the pending folder) of the imported collection.
    public var file: String?
    /// For deleteDeck: the deck's full name.
    public var deckName: String?
    public var date: Date
}

public struct LibraryImportResult: Sendable {
    public var format: PackageFormat
    public var merge: CollectionMerger.Summary
    public var missingMedia: [String]
}

/// Negoto keeps exactly one collection:
///
///     <root>/collections/<main id>/collection.anki2
///     <root>/collections/<main id>/media/
///     <root>/collections/<main id>/pending/        operations not yet uploaded by sync
public final class Library: @unchecked Sendable {
    public static let mainID = UUID(uuidString: "00000000-0000-4000-8000-00000000A0C1")!

    public let root: URL
    /// When true, imports/deletions are recorded so that sync can replay them (set while sync is on).
    public var recordsPendingOperations = false
    private let lock = NSRecursiveLock()

    public var collectionsDir: URL { root.appendingPathComponent("collections", isDirectory: true) }
    public var mainFolder: URL { folder(for: Self.mainID) }
    public var mainCollectionFile: URL { collectionFile(for: Self.mainID) }
    public var mainMediaFolder: URL { mediaFolder(for: Self.mainID) }
    var pendingFolder: URL { mainFolder.appendingPathComponent("pending", isDirectory: true) }
    var pendingList: URL { pendingFolder.appendingPathComponent("operations.json") }
    var tmpFolder: URL { root.appendingPathComponent("tmp", isDirectory: true) }

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: collectionsDir, withIntermediateDirectories: true)
    }

    public func folder(for id: UUID) -> URL { collectionsDir.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func collectionFile(for id: UUID) -> URL { folder(for: id).appendingPathComponent(PackageImporter.collectionFileName) }
    public func mediaFolder(for id: UUID) -> URL { folder(for: id).appendingPathComponent(PackageImporter.mediaFolderName, isDirectory: true) }

    // MARK: Main collection

    /// Creates the collection if needed and merges collections left over from older versions.
    public func prepare() throws {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try fm.createDirectory(at: mainMediaFolder, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: mainCollectionFile.path) {
            try AnkiCollection.createEmpty(at: mainCollectionFile)
        }
        try migrateLegacyCollections()
    }

    /// Opens a new connection to the collection.
    public func openMain() throws -> AnkiCollection {
        try AnkiCollection(path: mainCollectionFile, mediaFolder: mainMediaFolder)
    }

    /// Older versions kept one collection per imported file; merge them into the main one.
    func migrateLegacyCollections() throws {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: collectionsDir, includingPropertiesForKeys: nil)) ?? []
        let legacy = dirs.filter { UUID(uuidString: $0.lastPathComponent) != nil && $0.lastPathComponent != Self.mainID.uuidString }
        guard !legacy.isEmpty else { return }
        let main = try openMain()
        defer { main.db.close() }
        for dir in legacy.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let file = dir.appendingPathComponent(PackageImporter.collectionFileName)
            if fm.fileExists(atPath: file.path) {
                let source = try AnkiCollection(path: file, mediaFolder: dir.appendingPathComponent(PackageImporter.mediaFolderName))
                try CollectionMerger.merge(source, into: main)
                source.db.close()
            }
            try fm.removeItem(at: dir)
        }
    }

    // MARK: Import

    /// Imports a package into the collection: `.merge` adds its contents (like Anki's .apkg import),
    /// `.replace` makes the collection exactly the package (like Anki's .colpkg import).
    public func importPackage(at url: URL, mode: PendingOperation.Kind = .merge,
                              progress: ((Double) -> Void)? = nil) throws -> LibraryImportResult {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let work = tmpFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let imported = try PackageImporter.importPackage(at: url, into: work) { progress?($0 * 0.7) }
        let source = try AnkiCollection(path: imported.collectionFile, mediaFolder: imported.mediaFolder)
        defer { source.db.close() }
        let main = try openMain()
        defer { main.db.close() }
        if mode == .replace { try resetMain(main) }
        let summary = try CollectionMerger.merge(source, into: main, sourceMedia: imported.mediaFolder)
        if mode == .replace, source.fsrsEnabled { try main.setFSRS(true) }
        progress?(0.95)
        if recordsPendingOperations {
            // Keep the (media-renamed) source so the import can be replayed on top of a newer shared base.
            source.db.close()
            let name = "\(UUID().uuidString).anki2"
            try fm.createDirectory(at: pendingFolder, withIntermediateDirectories: true)
            try fm.copyItem(at: imported.collectionFile, to: pendingFolder.appendingPathComponent(name))
            try addPending(PendingOperation(kind: mode, file: name, deckName: nil, date: Date()))
        }
        progress?(1)
        return LibraryImportResult(format: imported.format, merge: summary, missingMedia: imported.missingMedia)
    }

    /// Empties the collection (keeps nothing but a Default deck and options).
    func resetMain(_ main: AnkiCollection) throws {
        let fresh = tmpFolder.appendingPathComponent("\(UUID().uuidString).anki2")
        try FileManager.default.createDirectory(at: tmpFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fresh) }
        try AnkiCollection.createEmpty(at: fresh)
        try main.replaceContents(withCollectionAt: fresh)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: mainMediaFolder.path)) ?? [] where !name.hasPrefix(".") {
            try? FileManager.default.removeItem(at: mainMediaFolder.appendingPathComponent(name))
        }
    }

    /// Deletes a deck (and subdecks/cards) and records it for sync.
    public func deleteDeck(_ id: Int64, in collection: AnkiCollection) throws {
        lock.lock(); defer { lock.unlock() }
        guard let name = collection.decks[id]?.name else { return }
        try collection.deleteDeck(id)
        if recordsPendingOperations {
            try addPending(PendingOperation(kind: .deleteDeck, file: nil, deckName: name, date: Date()))
        }
    }

    // MARK: Pending operations

    public func pendingOperations() -> [PendingOperation] {
        guard let data = try? Data(contentsOf: pendingList) else { return [] }
        return (try? JSONDecoder().decode([PendingOperation].self, from: data)) ?? []
    }

    func addPending(_ op: PendingOperation) throws {
        try FileManager.default.createDirectory(at: pendingFolder, withIntermediateDirectories: true)
        let ops = pendingOperations() + [op]
        try JSONEncoder().encode(ops).write(to: pendingList, options: .atomic)
    }

    func clearPending() {
        try? FileManager.default.removeItem(at: pendingFolder)
    }

    func pendingFile(_ name: String) -> URL { pendingFolder.appendingPathComponent(name) }

    /// Records the whole current collection as a pending merge (used when a device with its own
    /// decks joins an existing sync).
    func snapshotMainAsPending(_ main: AnkiCollection) throws {
        clearPending()
        try FileManager.default.createDirectory(at: pendingFolder, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).anki2"
        try main.db.execute("VACUUM INTO '\(pendingFile(name).path.replacingOccurrences(of: "'", with: "''"))'")
        try addPending(PendingOperation(kind: .merge, file: name, deckName: nil, date: Date()))
    }

    /// Re-applies pending operations to the collection (after it was replaced by a newer shared base).
    func replayPending(on main: AnkiCollection) throws {
        for op in pendingOperations() {
            switch op.kind {
            case .merge, .replace:
                guard let file = op.file, FileManager.default.fileExists(atPath: pendingFile(file).path) else { continue }
                let source = try AnkiCollection(path: pendingFile(file), mediaFolder: mainMediaFolder)
                if op.kind == .replace {
                    let fresh = tmpFolder.appendingPathComponent("\(UUID().uuidString).anki2")
                    try FileManager.default.createDirectory(at: tmpFolder, withIntermediateDirectories: true)
                    try AnkiCollection.createEmpty(at: fresh)
                    try main.replaceContents(withCollectionAt: fresh)
                    try? FileManager.default.removeItem(at: fresh)
                }
                try CollectionMerger.merge(source, into: main, sourceMedia: mainMediaFolder, now: op.date)
                source.db.close()
            case .deleteDeck:
                if let name = op.deckName, let deck = main.decks.values.first(where: { $0.name == name }) {
                    try main.deleteDeck(deck.id)
                }
            }
        }
    }

    // MARK: Daily maintenance

    private var stateFile: URL { mainFolder.appendingPathComponent("library-state.json") }

    /// Unburies cards once per day, as Anki does on the first open of a new day.
    public func performDailyMaintenance(_ col: AnkiCollection) {
        let today = col.timingToday().daysElapsed
        let last = (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) }?["lastUnburiedDay"]
        guard last != today else { return }
        try? col.unburyCards()
        try? JSONEncoder().encode(["lastUnburiedDay": today]).write(to: stateFile, options: .atomic)
    }
}

extension AnkiCollection {
    /// Replaces all notes, cards, review history and configuration with those of another
    /// schema 11 collection file, in place (other connections stay valid).
    public func replaceContents(withCollectionAt url: URL) throws {
        let path = url.path.replacingOccurrences(of: "'", with: "''")
        try db.execute("ATTACH DATABASE '\(path)' AS incoming")
        defer { try? db.execute("DETACH DATABASE incoming") }
        try db.transaction {
            for table in ["notes", "cards", "revlog", "graves"] {
                try db.run("DELETE FROM main.\(table)")
                try db.run("INSERT INTO main.\(table) SELECT * FROM incoming.\(table)")
            }
            try db.run("""
                UPDATE main.col SET crt = (SELECT crt FROM incoming.col), mod = (SELECT mod FROM incoming.col),
                conf = (SELECT conf FROM incoming.col), models = (SELECT models FROM incoming.col),
                decks = (SELECT decks FROM incoming.col), dconf = (SELECT dconf FROM incoming.col)
                """)
            if db.tableExists("negoto_deleted_revlog") { try db.run("DELETE FROM negoto_deleted_revlog") }
        }
        try reload()
    }
}
