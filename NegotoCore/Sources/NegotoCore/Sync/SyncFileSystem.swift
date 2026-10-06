import Foundation

/// File operations used by the sync engine. The app provides an implementation that coordinates
/// access to iCloud Drive (downloading placeholders etc.); tests use `PlainFileSystem`.
public protocol SyncFileSystem: Sendable {
    func read(_ url: URL) throws -> Data
    /// Atomically replaces the file's contents.
    func write(_ data: Data, to url: URL) throws
    /// Copies a file, replacing the destination if it exists.
    func copy(from source: URL, to destination: URL) throws
    /// Names of the entries in a directory (cloud placeholders are reported under their real name).
    func list(_ directory: URL) throws -> [String]
    func exists(_ url: URL) -> Bool
    func createDirectory(_ url: URL) throws
    func remove(_ url: URL) throws
}

public struct PlainFileSystem: SyncFileSystem {
    public init() {}

    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    public func write(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }

    public func copy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let tmp = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try fm.copyItem(at: source, to: tmp)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: tmp, to: destination)
    }

    public func list(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap(Self.realName)
    }

    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func remove(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// iCloud Drive represents files that aren't downloaded yet as ".name.icloud".
    /// Returns the real name, or nil for hidden/temporary files.
    public static func realName(_ name: String) -> String? {
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            return String(name.dropFirst().dropLast(".icloud".count))
        }
        if name.hasPrefix(".") { return nil }
        return name
    }
}
