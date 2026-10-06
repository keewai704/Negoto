import Foundation

/// Metadata for one imported collection.
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
    /// nil = follow the collection's own setting.
    public var useFSRS: Bool?
    public var lastUnburiedDay: Int?
}

/// Manages the on-disk library of imported collections:
///
///     <root>/collections/<uuid>/info.json
///     <root>/collections/<uuid>/collection.anki2
///     <root>/collections/<uuid>/media/
public final class Library: @unchecked Sendable {
    public let root: URL
    public var collectionsDir: URL { root.appendingPathComponent("collections", isDirectory: true) }

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: collectionsDir, withIntermediateDirectories: true)
    }

    public func folder(for id: UUID) -> URL { collectionsDir.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func collectionFile(for id: UUID) -> URL { folder(for: id).appendingPathComponent(PackageImporter.collectionFileName) }
    public func mediaFolder(for id: UUID) -> URL { folder(for: id).appendingPathComponent(PackageImporter.mediaFolderName, isDirectory: true) }
    private func infoFile(for id: UUID) -> URL { folder(for: id).appendingPathComponent("info.json") }

    public func list() -> [CollectionInfo] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: collectionsDir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("info.json")) else { return nil }
            return try? decoder.decode(CollectionInfo.self, from: data)
        }.sorted { $0.importedAt < $1.importedAt }
    }

    public func save(_ info: CollectionInfo) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: infoFile(for: info.id), options: .atomic)
    }

    /// Imports a package as a new collection. On failure nothing is left behind.
    public func importPackage(at url: URL, progress: ((Double) -> Void)? = nil) throws -> CollectionInfo {
        let id = UUID()
        let dest = folder(for: id)
        do {
            let summary = try PackageImporter.importPackage(at: url, into: dest, progress: progress)
            var name = url.deletingPathExtension().lastPathComponent
            if name.isEmpty || name == "collection" { name = "Anki Collection" }
            let info = CollectionInfo(id: id, name: name, sourceFilename: url.lastPathComponent, importedAt: Date(),
                                      format: summary.format.rawValue, noteCount: summary.noteCount,
                                      cardCount: summary.cardCount, mediaCount: summary.mediaCount,
                                      missingMediaCount: summary.missingMedia.count, useFSRS: nil, lastUnburiedDay: nil)
            try save(info)
            return info
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
    }

    public func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: folder(for: id))
    }

    public func open(_ info: CollectionInfo) throws -> AnkiCollection {
        let col = try AnkiCollection(path: collectionFile(for: info.id), mediaFolder: mediaFolder(for: info.id))
        col.fsrsOverride = info.useFSRS
        // Unbury cards once per day, as Anki does on the first open of a new day.
        let today = col.timingToday().daysElapsed
        if info.lastUnburiedDay != today {
            try? col.unburyCards()
            var updated = info
            updated.lastUnburiedDay = today
            try? save(updated)
        }
        return col
    }
}
