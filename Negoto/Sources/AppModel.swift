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

    var id: String { "\(collectionID.uuidString)-\(deck.id)" }
    var ref: DeckRef { DeckRef(collectionID: collectionID, deckID: deck.id) }
}

struct DeckRef: Hashable, Codable {
    var collectionID: UUID
    var deckID: Int64
}

@MainActor
@Observable
final class AppModel {
    let library: Library
    let supportDirectory: URL
    private(set) var collections: [CollectionInfo] = []
    private(set) var deckTrees: [UUID: [DeckNode]] = [:]
    var importStatus: ImportStatus?
    var alertMessage: String?
    /// Bumped whenever study data changes so views can refresh.
    private(set) var revision = 0

    struct ImportStatus: Equatable {
        var filename: String
        var progress: Double
    }

    @ObservationIgnored private var openCollections: [UUID: AnkiCollection] = [:]

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let root = base.appendingPathComponent("Negoto", isDirectory: true)
        library = Library(root: root)
        supportDirectory = SupportFiles.install(into: root)
        cleanupInbox()
        reload()
    }

    var libraryRoot: URL { library.root }

    func reload() {
        collections = library.list()
        refreshCounts()
    }

    func collection(_ id: UUID) -> AnkiCollection? {
        if let c = openCollections[id] { return c }
        guard let info = collections.first(where: { $0.id == id }) else { return nil }
        do {
            let c = try library.open(info)
            openCollections[id] = c
            return c
        } catch {
            alertMessage = "コレクションを開けませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    func info(_ id: UUID) -> CollectionInfo? { collections.first { $0.id == id } }

    func deck(_ ref: DeckRef) -> Deck? { collection(ref.collectionID)?.decks[ref.deckID] }

    // MARK: Counts

    func refreshCounts() {
        var trees: [UUID: [DeckNode]] = [:]
        for info in collections {
            guard let col = collection(info.id) else { continue }
            trees[info.id] = Self.buildTree(col, collectionID: info.id)
        }
        deckTrees = trees
        revision += 1
    }

    static func buildTree(_ col: AnkiCollection, collectionID: UUID) -> [DeckNode] {
        let decks = col.sortedDecks.filter { !$0.isFiltered }
        var nodesByName: [String: DeckNode] = [:]
        var childrenOf: [String: [String]] = [:]
        var roots: [String] = []
        for deck in decks {
            nodesByName[deck.name] = DeckNode(collectionID: collectionID, deck: deck, counts: col.counts(for: deck.id), children: nil)
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
        let built = roots.compactMap(build)
        // Hide an empty "Default" deck like Anki does.
        return built.filter { node in
            !(node.deck.id == 1 && node.children == nil && col.totalCards(in: 1) == 0)
        }
    }

    func dataChanged() { refreshCounts() }

    /// Recomputes counts for one collection only (cheaper than a full refresh after each answer).
    func refreshCounts(for id: UUID) {
        guard let col = collection(id) else { return }
        deckTrees[id] = Self.buildTree(col, collectionID: id)
        revision += 1
    }

    // MARK: Import

    func importFiles(_ urls: [URL]) {
        Task { @MainActor in
            for url in urls { await importFile(url) }
        }
    }

    func importFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let filename = url.lastPathComponent
        importStatus = ImportStatus(filename: filename, progress: 0)
        // Copy first: the source may be a security-scoped or Inbox URL that disappears.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)")
        let staged = staging.appendingPathComponent(filename.isEmpty ? "deck.apkg" : filename)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var coordError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { readURL in
                do { try FileManager.default.copyItem(at: readURL, to: staged) } catch { copyError = error }
            }
            if let copyError { throw copyError }
            if let coordError { throw coordError }
        } catch {
            importStatus = nil
            alertMessage = "ファイルを読み込めませんでした: \(error.localizedDescription)"
            return
        }
        let library = self.library
        let result: Result<CollectionInfo, Error> = await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                let info = try library.importPackage(at: staged) { p in
                    Task { @MainActor [weak self] in self?.importStatus?.progress = p }
                }
                return .success(info)
            } catch {
                return .failure(error)
            }
        }.value
        importStatus = nil
        switch result {
        case .success(let info):
            reload()
            if info.missingMediaCount > 0 {
                alertMessage = "「\(info.name)」を読み込みました。\(info.missingMediaCount)個のメディアファイルがパッケージに含まれていませんでした。"
            }
        case .failure(let error):
            alertMessage = "「\(filename)」を読み込めませんでした。\n\(error.localizedDescription)"
        }
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
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
        Task { @MainActor in
            for file in files {
                await importFile(file)
                let target = doneDir.appendingPathComponent(file.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.moveItem(at: file, to: target)
            }
        }
    }

    private func cleanupInbox() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: docs.appendingPathComponent("Inbox"))
    }

    // MARK: Management

    func delete(_ id: UUID) {
        openCollections[id]?.db.close()
        openCollections[id] = nil
        do { try library.delete(id) } catch { alertMessage = error.localizedDescription }
        reload()
    }

    func rename(_ id: UUID, to name: String) {
        guard var info = info(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        info.name = trimmed
        try? library.save(info)
        reload()
    }

    func setFSRS(_ id: UUID, _ value: Bool?) {
        guard var info = info(id) else { return }
        info.useFSRS = value
        try? library.save(info)
        openCollections[id]?.fsrsOverride = value
        collections = library.list()
    }

    func fsrsEnabled(_ id: UUID) -> Bool { collection(id)?.fsrsEnabled ?? false }
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
