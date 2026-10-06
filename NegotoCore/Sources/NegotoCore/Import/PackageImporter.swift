import Foundation
import ZIPFoundation

public enum ImportError: Error, LocalizedError {
    case unreadable(String)
    case unsupportedFormat(String)
    case noCollection

    public var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "The file could not be read: \(s)"
        case .unsupportedFormat(let s): return "Unsupported file: \(s)"
        case .noCollection: return "The package does not contain an Anki collection."
        }
    }
}

public struct ImportSummary: Sendable {
    public var collectionFile: URL
    public var mediaFolder: URL
    public var format: PackageFormat
    public var noteCount: Int
    public var cardCount: Int
    public var mediaCount: Int
    public var missingMedia: [String]
}

public enum PackageFormat: String, Sendable {
    /// collection.anki2 (Anki 2.0, schema 11)
    case legacy1
    /// collection.anki21 (Anki 2.1, schema 11)
    case legacy2
    /// collection.anki21b (Anki ≥2.1.50, zstd + schema 18, protobuf media map)
    case latest
    /// A bare SQLite collection file.
    case bareCollection
}

/// Imports `.apkg`, `.colpkg`, `.anki2`, `.anki21`, `.anki21b` into a self-contained folder:
///
///     destination/collection.anki2   – plain SQLite collection
///     destination/media/             – media files with their original names
public enum PackageImporter {
    public static let collectionFileName = "collection.anki2"
    public static let mediaFolderName = "media"

    public static func importPackage(at source: URL, into destination: URL,
                                     progress: ((Double) -> Void)? = nil) throws -> ImportSummary {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let mediaDir = destination.appendingPathComponent(mediaFolderName, isDirectory: true)
        try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let collectionURL = destination.appendingPathComponent(collectionFileName)
        try? fm.removeItem(at: collectionURL)

        let header = try readHeader(source)
        var format: PackageFormat
        var mediaCount = 0
        var missing: [String] = []

        if header.starts(with: [0x50, 0x4B]) {  // "PK" – zip
            (format, mediaCount, missing) = try importZip(source, collectionURL: collectionURL, mediaDir: mediaDir, progress: progress)
        } else if header.starts(with: Array("SQLite format 3".utf8)) {
            try fm.copyItem(at: source, to: collectionURL)
            format = .bareCollection
        } else if header.starts(with: Zstd.magic) {
            try decompressFile(source, to: collectionURL)
            format = .latest
        } else {
            throw ImportError.unsupportedFormat(source.lastPathComponent)
        }

        let col = try AnkiCollection(path: collectionURL, mediaFolder: mediaDir)
        try? col.db.execute("PRAGMA journal_mode = DELETE")
        try col.emptyFilteredDecks()
        try col.upgradeLegacyScheduling()
        let notes = try col.db.scalar("SELECT count() FROM notes").int
        let cards = try col.db.scalar("SELECT count() FROM cards").int
        col.db.close()
        progress?(1)
        return ImportSummary(collectionFile: collectionURL, mediaFolder: mediaDir, format: format,
                             noteCount: notes, cardCount: cards, mediaCount: mediaCount, missingMedia: missing)
    }

    private static func readHeader(_ url: URL) throws -> [UInt8] {
        guard let h = try? FileHandle(forReadingFrom: url) else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        defer { try? h.close() }
        return [UInt8](h.readData(ofLength: 16))
    }

    private static func decompressFile(_ src: URL, to dst: URL) throws {
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let out = try FileHandle(forWritingTo: dst)
        defer { try? out.close() }
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        let decoder = try Zstd.StreamDecoder()
        while true {
            let chunk = input.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            try decoder.feed(chunk) { out.write($0) }
        }
        try decoder.finish()
    }

    // MARK: - Zip packages

    private static func importZip(_ source: URL, collectionURL: URL, mediaDir: URL,
                                  progress: ((Double) -> Void)?) throws -> (PackageFormat, Int, [String]) {
        let archive: Archive
        do {
            archive = try Archive(url: source, accessMode: .read)
        } catch {
            throw ImportError.unreadable("\(source.lastPathComponent): \(error.localizedDescription)")
        }
        var byName: [String: Entry] = [:]
        for entry in archive {
            // Some tools put everything in a sub-folder; key by last path component.
            let name = (entry.path as NSString).lastPathComponent
            if byName[name] == nil || !entry.path.contains("/") { byName[name] = entry }
        }

        // Prefer the newest collection format; older Anki versions find a stub in collection.anki2.
        let candidates: [(String, PackageFormat)] = [
            ("collection.anki21b", .latest), ("collection.anki21", .legacy2), ("collection.anki2", .legacy1),
        ]
        guard let (colName, format) = candidates.first(where: { byName[$0.0] != nil }), let colEntry = byName[colName] else {
            throw ImportError.noCollection
        }
        try extract(archive, colEntry, to: collectionURL, allowZstd: true)
        progress?(0.1)

        let isLatest = format == .latest || metaVersion(archive, byName) >= 3
        let mediaMap = try readMediaMap(archive, byName["media"], latest: isLatest)
        var count = 0
        var missing: [String] = []
        var usedNames = Set<String>()
        for (i, item) in mediaMap.enumerated() {
            guard let safe = sanitizeFilename(item.name), !usedNames.contains(safe) else { continue }
            usedNames.insert(safe)
            guard let entry = byName[item.zipName] else {
                missing.append(item.name)
                continue
            }
            do {
                try extract(archive, entry, to: mediaDir.appendingPathComponent(safe), allowZstd: isLatest)
                count += 1
            } catch {
                missing.append(item.name)
            }
            if i % 20 == 0 { progress?(0.1 + 0.85 * Double(i + 1) / Double(max(mediaMap.count, 1))) }
        }
        return (format, count, missing)
    }

    private static func metaVersion(_ archive: Archive, _ byName: [String: Entry]) -> Int {
        guard let entry = byName["meta"], let data = try? readAll(archive, entry) else { return 0 }
        return Int(ProtoMessage(data).uint(1) ?? 0)
    }

    struct MediaItem { var name: String; var zipName: String }

    private static func readMediaMap(_ archive: Archive, _ entry: Entry?, latest: Bool) throws -> [MediaItem] {
        guard let entry else { return [] }
        var data = try readAll(archive, entry)
        if Zstd.isCompressed(data) {
            data = try Zstd.decompress(data)
        } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Legacy: {"0": "file.jpg", ...}
            return obj.compactMap { key, value in
                guard let name = value as? String else { return nil }
                return MediaItem(name: name, zipName: key)
            }.sorted { (Int($0.zipName) ?? 0) < (Int($1.zipName) ?? 0) }
        }
        // Latest: protobuf MediaEntries { repeated MediaEntry { name=1, size=2, sha1=3, legacy_zip_filename=255 } }
        let entries = ProtoMessage(data).messages(1)
        return entries.enumerated().map { i, e in
            let zipName = e.uint(255).map { String($0) } ?? String(i)
            return MediaItem(name: e.string(1) ?? "", zipName: zipName)
        }
    }

    static func sanitizeFilename(_ name: String) -> String? {
        var n = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
        n = n.replacingOccurrences(of: "\u{0}", with: "")
        guard !n.isEmpty, n != ".", n != ".." else { return nil }
        return n
    }

    private static func readAll(_ archive: Archive, _ entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry, bufferSize: 1 << 16, skipCRC32: true) { data.append($0) }
        return data
    }

    /// Streams an entry to disk, transparently zstd-decompressing it if needed.
    private static func extract(_ archive: Archive, _ entry: Entry, to url: URL, allowZstd: Bool) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }
        var decoder: Zstd.StreamDecoder?
        var decided = !allowZstd
        var pending = Data()
        _ = try archive.extract(entry, bufferSize: 1 << 16, skipCRC32: true) { chunk in
            if !decided {
                pending.append(chunk)
                guard pending.count >= 4 else { return }
                decided = true
                if Zstd.isCompressed(pending) { decoder = try Zstd.StreamDecoder() }
                let first = pending
                pending = Data()
                if let decoder { try decoder.feed(first) { out.write($0) } } else { out.write(first) }
                return
            }
            if let decoder { try decoder.feed(chunk) { out.write($0) } } else { out.write(chunk) }
        }
        if !decided, !pending.isEmpty { out.write(pending) }
        try decoder?.finish()
    }
}
