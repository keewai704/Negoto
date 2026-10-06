import Foundation
import NegotoCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ankiPackage = UTType(importedAs: "net.ankiweb.apkg")
    static let ankiCollectionPackage = UTType(importedAs: "net.ankiweb.colpkg")
    static let ankiCollection = UTType(importedAs: "net.ankiweb.anki2")
}

/// A deck in the sidebar tree, with today's counts.
struct DeckNode: Identifiable, Hashable {
    var collectionID: UUID
    var deck: Deck
    var counts: DeckCounts
    var children: [DeckNode]?

    var id: Int64 { deck.id }
    var ref: DeckRef { DeckRef(collectionID: collectionID, deckID: deck.id) }
}

struct DeckRef: Hashable, Codable, Identifiable {
    var collectionID: UUID = Library.mainID
    var deckID: Int64
    var id: Int64 { deckID }

    /// Every deck in the collection.
    static let all = DeckRef(deckID: AnkiCollection.allDecksID)
}

@MainActor
@Observable
final class AppModel {
    let library: Library
    let supportDirectory: URL
    private(set) var deckTree: [DeckNode] = []
    var importStatus: ImportStatus?
    /// The deck being studied (presented full screen), if any.
    var studyTarget: DeckRef?
    /// A collection package waiting for the user to choose replace or merge.
    var pendingCollectionImport: URL?
    let sync = SyncController()
    var alertMessage: String?
    /// Bumped whenever study data changes so views can refresh.
    private(set) var revision = 0

    struct ImportStatus: Equatable {
        var filename: String
        var progress: Double
    }

    @ObservationIgnored private var main: AnkiCollection?

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let root = base.appendingPathComponent("Negoto", isDirectory: true)
        library = Library(root: root)
        supportDirectory = SupportFiles.install(into: root)
        do {
            try library.prepare()  // also merges collections from older versions into one
        } catch {
            alertMessage = "コレクションを準備できませんでした: \(error.localizedDescription)"
        }
        cleanupInbox()
        refreshCounts()
        sync.attach(self)
        if Self.isUITesting, isEmpty, let demo = Bundle.main.url(forResource: "UITestDemo", withExtension: "apkg") {
            importFiles([demo])
        }
    }

    /// UI tests (screenshots in CI) start the app with a demo deck and without alerts.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uitest-demo")

    var libraryRoot: URL { library.root }

    /// The (single) collection.
    var collectionHandle: AnkiCollection? {
        if let main { return main }
        do {
            let c = try library.openMain()
            library.performDailyMaintenance(c)
            main = c
            return c
        } catch {
            alertMessage = "コレクションを開けませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    /// Kept for call sites written for multiple collections; there is only one.
    func collection(_ id: UUID) -> AnkiCollection? { collectionHandle }

    func deck(_ ref: DeckRef) -> Deck? { collectionHandle?.decks[ref.deckID] }

    func displayName(_ ref: DeckRef) -> String {
        ref.deckID == AnkiCollection.allDecksID ? "すべてのデッキ" : (deck(ref)?.baseName ?? "")
    }

    func startStudy(_ ref: DeckRef) { studyTarget = ref }

    /// Today's counts over every deck.
    var totalCounts: DeckCounts {
        deckTree.reduce(DeckCounts()) { acc, n in
            DeckCounts(new: acc.new + n.counts.new, learning: acc.learning + n.counts.learning, review: acc.review + n.counts.review)
        }
    }

    func node(for deckID: Int64) -> DeckNode? {
        func search(_ nodes: [DeckNode]) -> DeckNode? {
            for n in nodes {
                if n.deck.id == deckID { return n }
                if let c = n.children, let found = search(c) { return found }
            }
            return nil
        }
        return search(deckTree)
    }

    var deckTrees: [UUID: [DeckNode]] { [Library.mainID: deckTree] }

    var isEmpty: Bool { (collectionHandle?.cardCount ?? 0) == 0 }

    /// Re-reads the collection after it was changed by another connection (import, sync).
    func reload() {
        try? collectionHandle?.reload()
        refreshCounts()
    }

    // MARK: Counts

    func refreshCounts() {
        if let col = collectionHandle {
            library.performDailyMaintenance(col)
            deckTree = Self.buildTree(col)
        }
        revision += 1
    }

    func refreshCounts(for id: UUID) { refreshCounts() }

    static func buildTree(_ col: AnkiCollection) -> [DeckNode] {
        let decks = col.sortedDecks.filter { !$0.isFiltered }
        var nodesByName: [String: DeckNode] = [:]
        var childrenOf: [String: [String]] = [:]
        var roots: [String] = []
        for deck in decks {
            nodesByName[deck.name] = DeckNode(collectionID: Library.mainID, deck: deck, counts: col.counts(for: deck.id), children: nil)
            if let parent = deck.parentName, nodesByName[parent] != nil {
                childrenOf[parent, default: []].append(deck.name)
            } else {
                roots.append(deck.name)
            }
        }
        func build(_ name: String) -> DeckNode? {
            guard var node = nodesByName[name] else { return nil }
            let kids = (childrenOf[name] ?? []).compactMap(build)
            node.children = kids.isEmpty ? nil : kids
            return node
        }
        // Hide an empty "Default" deck like Anki does.
        return roots.compactMap(build).filter { node in
            !(node.deck.id == 1 && node.children == nil && col.totalCards(in: 1) == 0)
        }
    }

    // MARK: Import

    static let collectionExtensions: Set<String> = ["colpkg", "anki2", "anki21", "anki21b"]

    func importFiles(_ urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if Self.collectionExtensions.contains(url.pathExtension.lowercased()) && !isEmpty {
                    // A whole collection: ask whether to replace or merge (handled by RootView).
                    pendingCollectionImport = await stage(url)
                } else if let staged = await stage(url) {
                    await importStaged(staged, mode: .merge)
                }
            }
        }
    }

    func resolveCollectionImport(_ mode: PendingOperation.Kind?) {
        guard let staged = pendingCollectionImport else { return }
        pendingCollectionImport = nil
        guard let mode else {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            return
        }
        Task { await importStaged(staged, mode: mode) }
    }

    /// Copies the file somewhere we own: the source may be security-scoped or an Inbox file that disappears.
    private func stage(_ url: URL) async -> URL? {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)")
        let filename = url.lastPathComponent.isEmpty ? "deck.apkg" : url.lastPathComponent
        let staged = staging.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var coordError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { readURL in
                do { try FileManager.default.copyItem(at: readURL, to: staged) } catch { copyError = error }
            }
            if let copyError { throw copyError }
            if let coordError { throw coordError }
            return staged
        } catch {
            alertMessage = "ファイルを読み込めませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    private func importStaged(_ staged: URL, mode: PendingOperation.Kind) async {
        let filename = staged.lastPathComponent
        // Don't import while a sync is rewriting the collection.
        while sync.isSyncing { try? await Task.sleep(for: .milliseconds(200)) }
        importStatus = ImportStatus(filename: filename, progress: 0)
        let library = self.library
        let result: Result<LibraryImportResult, Error> = await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
            do {
                return .success(try library.importPackage(at: staged, mode: mode) { p in
                    Task { @MainActor [weak self] in self?.importStatus?.progress = p }
                })
            } catch {
                return .failure(error)
            }
        }.value
        importStatus = nil
        switch result {
        case .success(let r):
            reload()
            sync.requestSync()
            var lines = ["「\(filename)」を読み込みました。", "追加: \(r.merge.addedNotes)ノート・\(r.merge.addedCards)カード"]
            if r.merge.skippedNotes + r.merge.updatedNotes > 0 {
                lines.append("既にあるノート: \(r.merge.skippedNotes + r.merge.updatedNotes)件（重複して追加していません）")
            }
            if !r.missingMedia.isEmpty { lines.append("パッケージに含まれていないメディア: \(r.missingMedia.count)件") }
            if !Self.isUITesting { alertMessage = lines.joined(separator: "\n") }
        case .failure(let error):
            alertMessage = "「\(filename)」を読み込めませんでした。\n\(error.localizedDescription)"
        }
    }

    /// Imports packages the user dropped into the app's folder in the Files app.
    func importFromDocumentsFolder() {
        guard importStatus == nil,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let exts: Set<String> = ["apkg", "colpkg", "anki2", "anki21", "anki21b"]
        let files = ((try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? [])
            .filter { exts.contains($0.pathExtension.lowercased()) }
        guard !files.isEmpty else { return }
        let doneDir = docs.appendingPathComponent("読み込み済み", isDirectory: true)
        try? FileManager.default.createDirectory(at: doneDir, withIntermediateDirectories: true)
        var staged: [URL] = []
        for file in files {
            let target = doneDir.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            if (try? FileManager.default.moveItem(at: file, to: target)) != nil { staged.append(target) }
        }
        importFiles(staged)
    }

    private func cleanupInbox() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("Inbox"))
    }

    // MARK: Decks

    func renameDeck(_ id: Int64, to name: String) {
        do { try collectionHandle?.renameDeck(id, to: name) } catch { alertMessage = error.localizedDescription }
        refreshCounts()
        sync.requestSync()
    }

    func deleteDeck(_ id: Int64) {
        guard let col = collectionHandle else { return }
        do { try library.deleteDeck(id, in: col) } catch { alertMessage = error.localizedDescription }
        refreshCounts()
        sync.requestSync()
    }

    func createDeck(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do { try collectionHandle?.findOrCreateDeck(named: trimmed) } catch { alertMessage = error.localizedDescription }
        refreshCounts()
        sync.requestSync()
    }

    var fsrsEnabled: Bool { collectionHandle?.fsrsEnabled ?? false }

    func setFSRS(_ enabled: Bool) {
        do { try collectionHandle?.setFSRS(enabled) } catch { alertMessage = error.localizedDescription }
        refreshCounts()
        sync.requestSync()
    }

    func optionsChanged() {
        refreshCounts()
        sync.requestSync()
    }
}

/// Copies bundled web resources (MathJax) next to the collections, so card pages can load them.
enum SupportFiles {
    static func install(into root: URL) -> URL {
        let dir = root.appendingPathComponent("support", isDirectory: true)
        let mathjaxDir = dir.appendingPathComponent("mathjax", isDirectory: true)
        try? FileManager.default.createDirectory(at: mathjaxDir, withIntermediateDirectories: true)
        if let src = Bundle.main.url(forResource: "tex-svg-full", withExtension: "js") {
            let dst = mathjaxDir.appendingPathComponent("tex-svg-full.js")
            let srcSize = (try? FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int) ?? 0
            let dstSize = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? -1
            if srcSize != dstSize {
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }
        return dir
    }
}
