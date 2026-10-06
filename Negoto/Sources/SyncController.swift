import Foundation
import NegotoCore
import Observation
import UIKit

/// Where the shared sync folder lives.
enum SyncMode: String, CaseIterable, Identifiable {
    /// The app's own iCloud container (needs an iCloud-enabled signature). Shown as "Negoto" in iCloud Drive.
    case container
    /// A folder the user picked in iCloud Drive (works with any signature, including free Apple IDs).
    case folder
    case off

    var id: String { rawValue }
}

/// Syncs decks and study progress through iCloud.
///
/// If the app was signed with iCloud capability, its iCloud container is used automatically.
/// Otherwise the user picks a folder in iCloud Drive, which needs no entitlement at all.
@MainActor
@Observable
final class SyncController {
    private(set) var folderName: String?
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastMessage: String?
    private(set) var lastError: String?
    /// The iCloud container, if this build's signature includes one and the user is signed in to iCloud.
    private(set) var containerURL: URL?
    private(set) var containerChecked = false
    private(set) var preferredMode: SyncMode?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var pending = false
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var identityObserver: NSObjectProtocol?

    private static let bookmarkKey = "syncFolderBookmark"
    private static let modeKey = "syncMode"
    private static let autoKey = "syncAutomatically"
    private static let deviceKey = "syncDeviceID"
    private static let lastSyncKey = "lastSyncDate"
    /// Subfolder created inside the chosen folder / the container's Documents.
    static let folderName = "NegotoSync"

    let signing = SigningInfo.current

    /// The mode actually in use: an explicit choice if possible, otherwise the container when
    /// available, otherwise a previously chosen folder.
    var mode: SyncMode {
        switch preferredMode {
        case .off: return .off
        case .folder: return folderName != nil ? .folder : (containerURL != nil ? .container : .off)
        case .container, nil:
            if containerURL != nil { return .container }
            return folderName != nil ? .folder : .off
        }
    }

    var isConfigured: Bool { mode != .off }

    var locationDescription: String {
        switch mode {
        case .container: return "iCloud Drive › Negoto"
        case .folder: return "iCloud Drive › \(folderName ?? "")"
        case .off: return "オフ"
        }
    }

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
        preferredMode = defaults.string(forKey: Self.modeKey).flatMap(SyncMode.init(rawValue:))
        if let url = resolveFolder() { folderName = url.lastPathComponent }
        detectContainer()
        identityObserver = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil,
                                                                  queue: .main) { [weak self] _ in
            Task { @MainActor in self?.detectContainer() }
        }
    }

    /// `url(forUbiquityContainerIdentifier:)` returns nil when the signature has no iCloud container
    /// (e.g. free Apple ID / unsigned builds) or the user isn't signed in to iCloud. It may block, so
    /// it runs off the main thread.
    func detectContainer() {
        let hasIdentity = FileManager.default.ubiquityIdentityToken != nil
        Task {
            var url: URL?
            if hasIdentity {
                url = await Task.detached(priority: .utility) {
                    FileManager.default.url(forUbiquityContainerIdentifier: nil)
                }.value
            }
            containerURL = url
            containerChecked = true
            requestSync()
        }
    }

    /// Why the iCloud container can't be used, for display.
    var containerUnavailableReason: String? {
        guard containerURL == nil else { return nil }
        if !containerChecked { return "確認中…" }
        if FileManager.default.ubiquityIdentityToken == nil && signing.hasICloudDocuments {
            return "この端末でiCloudにサインインしていないか、iCloud Driveがオフになっています。"
        }
        if signing.looksLikeFreeAccount {
            return "無料のApple IDで署名されたアプリはiCloudコンテナを使えません。iCloud Driveのフォルダを選んで同期してください。"
        }
        return "このアプリの署名にiCloudの権限が含まれていません。iCloud Driveのフォルダを選んで同期してください。"
    }

    func setMode(_ mode: SyncMode) {
        preferredMode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        lastError = nil
        if mode != .off { requestSync(force: true) }
    }

    // MARK: Folder

    func chooseFolder(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
            folderName = url.lastPathComponent
            setMode(.folder)
        } catch {
            lastError = "フォルダを登録できませんでした: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        setMode(.off)
        lastMessage = nil
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

    /// The shared sync root and the URL whose security scope must be held while accessing it.
    private func syncRoot() -> (root: URL, scoped: URL?)? {
        switch mode {
        case .container:
            guard let c = containerURL else { return nil }
            return (c.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(Self.folderName, isDirectory: true), nil)
        case .folder:
            guard let f = resolveFolder() else { return nil }
            return (f.appendingPathComponent(Self.folderName, isDirectory: true), f)
        case .off:
            return nil
        }
    }

    // MARK: Syncing

    /// Starts a sync if one is configured (and automatic sync is on, unless forced).
    func requestSync(force: Bool = false) {
        model?.library.recordsPendingOperations = isConfigured
        guard isConfigured, force || syncAutomatically else { return }
        if isSyncing || model?.importStatus != nil { pending = true; return }
        Task { await run() }
    }

    private func run() async {
        guard let model, let target = syncRoot() else {
            lastError = mode == .folder ? "同期フォルダにアクセスできません。設定からフォルダを選び直してください。" : nil
            return
        }
        let root = target.root, scoped = target.scoped
        isSyncing = true
        lastError = nil
        let engine = SyncEngine(library: model.library, remoteRoot: root,
                                deviceID: deviceID, deviceName: UIDevice.current.name, fs: ICloudFileSystem())
        let background = UIApplication.shared.beginBackgroundTask(withName: "NegotoSync")
        let result: Result<SyncEngine.Report, Error> = await Task.detached(priority: .utility) {
            let access = scoped?.startAccessingSecurityScopedResource() ?? false
            defer { if access { scoped?.stopAccessingSecurityScopedResource() } }
            do { return .success(try engine.sync()) } catch { return .failure(error) }
        }.value
        UIApplication.shared.endBackgroundTask(background)
        isSyncing = false

        switch result {
        case .success(let report):
            if report.changedLocalData || report.uploadedBase { model.reload() }
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

    private static func describe(_ r: SyncEngine.Report) -> String {
        var parts: [String] = []
        if r.uploadedBase { parts.append("デッキをアップロード") }
        if r.downloadedBase { parts.append("デッキをダウンロード") }
        if r.exportedCards > 0 { parts.append("\(r.exportedCards)枚の学習を送信") }
        if r.appliedCards > 0 || r.appliedReviews > 0 { parts.append("他の端末から\(r.appliedCards)枚の学習を反映") }
        if r.appliedSettings > 0 { parts.append("設定を\(r.appliedSettings)件反映") }
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
