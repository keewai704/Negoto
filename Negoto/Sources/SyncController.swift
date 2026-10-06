import Foundation
import NegotoCore
import Observation
import UIKit

/// Syncs decks and study progress through a folder the user picks in iCloud Drive.
///
/// Using a user-chosen folder (instead of an app iCloud container) needs no iCloud entitlement,
/// so it also works for sideloaded builds signed with a free Apple ID.
@MainActor
@Observable
final class SyncController {
    private(set) var folderName: String?
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastMessage: String?
    private(set) var lastError: String?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var pending = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let bookmarkKey = "syncFolderBookmark"
    private static let autoKey = "syncAutomatically"
    private static let deviceKey = "syncDeviceID"
    private static let lastSyncKey = "lastSyncDate"
    /// Subfolder created inside the chosen folder.
    static let folderName = "NegotoSync"

    var isConfigured: Bool { folderName != nil }

    var syncAutomatically: Bool {
        get { defaults.object(forKey: Self.autoKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.autoKey) }
    }

    var deviceID: String {
        if let id = defaults.string(forKey: Self.deviceKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.deviceKey)
        return id
    }

    func attach(_ model: AppModel) {
        self.model = model
        lastSyncDate = defaults.object(forKey: Self.lastSyncKey) as? Date
        if let url = resolveFolder() { folderName = url.lastPathComponent }
    }

    // MARK: Folder

    func chooseFolder(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
            folderName = url.lastPathComponent
            lastError = nil
            requestSync(force: true)
        } catch {
            lastError = "フォルダを登録できませんでした: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        folderName = nil
        lastMessage = nil
        lastError = nil
    }

    private func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    // MARK: Syncing

    /// Starts a sync if one is configured (and automatic sync is on, unless forced).
    func requestSync(force: Bool = false) {
        guard isConfigured, force || syncAutomatically else { return }
        if isSyncing { pending = true; return }
        Task { await run() }
    }

    private func run() async {
        guard let model, let folder = resolveFolder() else {
            lastError = "同期フォルダにアクセスできません。設定からフォルダを選び直してください。"
            return
        }
        isSyncing = true
        lastError = nil
        let engine = SyncEngine(library: model.library, remoteRoot: folder.appendingPathComponent(Self.folderName, isDirectory: true),
                                deviceID: deviceID, deviceName: UIDevice.current.name, fs: ICloudFileSystem())
        let background = UIApplication.shared.beginBackgroundTask(withName: "NegotoSync")
        let result: Result<SyncEngine.Report, Error> = await Task.detached(priority: .utility) {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            do { return .success(try engine.sync()) } catch { return .failure(error) }
        }.value
        UIApplication.shared.endBackgroundTask(background)
        isSyncing = false

        switch result {
        case .success(let report):
            for id in report.deletedRemotely { model.removeLocally(id) }
            if report.changedLocalData { model.reload() }
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Self.lastSyncKey)
            lastMessage = Self.describe(report)
            if !report.errors.isEmpty { lastError = report.errors.joined(separator: "\n") }
        case .failure(let error):
            lastError = "同期に失敗しました: \(error.localizedDescription)"
        }
        if pending {
            pending = false
            Task { await run() }
        }
    }

    /// Tells other devices that a collection was deleted.
    func propagateDeletion(_ id: UUID) {
        guard isConfigured, let model, let folder = resolveFolder() else { return }
        let engine = SyncEngine(library: model.library, remoteRoot: folder.appendingPathComponent(Self.folderName, isDirectory: true),
                                deviceID: deviceID, deviceName: UIDevice.current.name, fs: ICloudFileSystem())
        Task.detached(priority: .utility) {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            try? engine.markDeleted(id)
        }
    }

    private static func describe(_ r: SyncEngine.Report) -> String {
        var parts: [String] = []
        if !r.uploaded.isEmpty { parts.append("\(r.uploaded.count)件のデッキをアップロード") }
        if !r.downloaded.isEmpty { parts.append("\(r.downloaded.count)件のデッキをダウンロード") }
        if r.exportedCards > 0 { parts.append("\(r.exportedCards)枚の学習を送信") }
        if r.appliedCards > 0 || r.appliedReviews > 0 { parts.append("他の端末から\(r.appliedCards)枚の学習を反映") }
        if !r.deletedRemotely.isEmpty { parts.append("\(r.deletedRemotely.count)件のデッキを削除") }
        return parts.isEmpty ? "最新の状態です" : parts.joined(separator: "、")
    }
}

/// File access for iCloud Drive: coordinated reads/writes and downloading of cloud-only files.
struct ICloudFileSystem: SyncFileSystem {
    private func coordinate(read url: URL, _ body: (URL) throws -> Void) throws {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var coordError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            do { try body(u) } catch { bodyError = error }
        }
        if let bodyError { throw bodyError }
        if let coordError { throw coordError }
    }

    private func coordinate(write url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var coordError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordError) { u in
            do { try body(u) } catch { bodyError = error }
        }
        if let bodyError { throw bodyError }
        if let coordError { throw coordError }
    }

    func read(_ url: URL) throws -> Data {
        var data = Data()
        try coordinate(read: url) { data = try Data(contentsOf: $0) }
        return data
    }

    func write(_ data: Data, to url: URL) throws {
        try coordinate(write: url, options: .forReplacing) { try data.write(to: $0, options: .atomic) }
    }

    func copy(from source: URL, to destination: URL) throws {
        try? FileManager.default.startDownloadingUbiquitousItem(at: source)
        var coordError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: destination,
                                       options: .forReplacing, error: &coordError) { src, dst in
            do {
                let fm = FileManager.default
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("negoto-copy-\(UUID().uuidString)")
                try fm.copyItem(at: src, to: tmp)
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.moveItem(at: tmp, to: dst)
            } catch {
                bodyError = error
            }
        }
        if let bodyError { throw bodyError }
        if let coordError { throw coordError }
    }

    func list(_ directory: URL) throws -> [String] {
        Array(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap(PlainFileSystem.realName)))
    }

    func exists(_ url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return true }
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        return fm.fileExists(atPath: placeholder.path)
    }

    func createDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try coordinate(write: url, options: []) {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    func remove(_ url: URL) throws {
        guard exists(url) else { return }
        try coordinate(write: url, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
    }
}
