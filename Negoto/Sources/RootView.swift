import NegotoCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: DeckRef?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var detailPath = NavigationPath()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DeckListView(selection: $selection, showImporter: $showImporter)
                .navigationTitle("Negoto")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showImporter = true } label: { Label("インポート", systemImage: "square.and.arrow.down") }
                            .keyboardShortcut("o", modifiers: .command)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: { Label("設定", systemImage: "gearshape") }
                            .keyboardShortcut(",", modifiers: .command)
                    }
                    if model.sync.isConfigured {
                        ToolbarItem(placement: .topBarTrailing) {
                            if model.sync.isSyncing {
                                ProgressView()
                            } else {
                                Button { model.sync.requestSync(force: true) } label: {
                                    Label("iCloud Driveと同期", systemImage: model.sync.lastError == nil ? "arrow.triangle.2.circlepath.icloud" : "exclamationmark.icloud")
                                }
                                .keyboardShortcut("s", modifiers: [.command, .shift])
                            }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            NavigationStack(path: $detailPath) {
                Group {
                    if let selection, model.deck(selection) != nil {
                        DeckOverviewView(ref: selection, path: $detailPath)
                    } else {
                        ContentUnavailableView {
                            Label("デッキを選択", systemImage: "rectangle.stack")
                        } description: {
                            Text(model.isEmpty
                                 ? "Ankiのデッキ（.apkg / .colpkg）をインポートして学習を始めましょう。"
                                 : "左のリストから学習するデッキを選んでください。上位のデッキを選ぶと、その下のデッキもまとめて学習できます。")
                        } actions: {
                            if model.isEmpty {
                                Button("デッキをインポート") { showImporter = true }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .navigationDestination(for: StudyRoute.self) { route in
                    StudyView(ref: route.ref)
                }
                .navigationDestination(for: BrowseRoute.self) { route in
                    BrowseView(ref: route.ref)
                }
            }
        }
        .onChange(of: selection) { _, _ in detailPath = NavigationPath() }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: [.ankiPackage, .ankiCollectionPackage, .ankiCollection, .zip, .data],
                           allowsMultipleSelection: true) { urls in
                model.importFiles(urls)
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("コレクションを読み込みます", isPresented: Binding(
            get: { model.pendingCollectionImport != nil },
            set: { if !$0 && model.pendingCollectionImport != nil { model.resolveCollectionImport(nil) } }),
                            titleVisibility: .visible) {
            Button("今のデッキと統合する") { model.resolveCollectionImport(.merge) }
            Button("今のデッキを置き換える", role: .destructive) { model.resolveCollectionImport(.replace) }
            Button("キャンセル", role: .cancel) { model.resolveCollectionImport(nil) }
        } message: {
            Text("「\(model.pendingCollectionImport?.lastPathComponent ?? "")」はコレクション全体のファイルです。置き換えると、今あるデッキと学習履歴はすべて削除されます。")
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .overlay { if let status = model.importStatus { ImportProgressView(status: status) } }
        .alert("Negoto", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshCounts()
                model.importFromDocumentsFolder()
                model.sync.requestSync()
            } else if phase == .background {
                model.sync.requestSync()
            }
        }
    }
}

struct StudyRoute: Hashable { var ref: DeckRef }
struct BrowseRoute: Hashable { var ref: DeckRef }

struct ImportProgressView: View {
    var status: AppModel.ImportStatus

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: status.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                Text("読み込み中…").font(.headline)
                Text(status.filename).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct DeckListView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: DeckRef?
    @Binding var showImporter: Bool
    @AppStorage("collapsedDecks") private var collapsedStorage = ""
    @State private var renaming: Deck?
    @State private var newName = ""
    @State private var deleting: Deck?
    @State private var optionsDeck: Deck?

    private var collapsed: Set<Int64> {
        Set(collapsedStorage.split(separator: ",").compactMap { Int64($0) })
    }

    private func toggle(_ id: Int64) {
        var c = collapsed
        if c.contains(id) { c.remove(id) } else { c.insert(id) }
        collapsedStorage = c.map(String.init).joined(separator: ",")
    }

    /// The tree flattened into visible rows (children of collapsed decks are hidden).
    private var rows: [(node: DeckNode, depth: Int)] {
        var out: [(DeckNode, Int)] = []
        func walk(_ nodes: [DeckNode], _ depth: Int) {
            for n in nodes {
                out.append((n, depth))
                if let kids = n.children, !collapsed.contains(n.deck.id) { walk(kids, depth + 1) }
            }
        }
        walk(model.deckTree, 0)
        return out
    }

    var body: some View {
        List(selection: $selection) {
            if model.isEmpty {
                Section {
                    Button { showImporter = true } label: {
                        Label("Ankiデッキをインポート", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text("AnkiWebの共有デッキやAnkiからエクスポートした .apkg / .colpkg を読み込めます。ファイルアプリや他のアプリの「共有」からも開けます。")
                }
            }
            Section {
                ForEach(rows, id: \.node.id) { row in
                    DeckRow(node: row.node, depth: row.depth, isCollapsed: collapsed.contains(row.node.deck.id)) {
                        toggle(row.node.deck.id)
                    }
                    .tag(row.node.ref)
                    .contextMenu {
                        Button { optionsDeck = row.node.deck } label: { Label("学習オプション", systemImage: "slider.horizontal.3") }
                        Button { newName = row.node.deck.name; renaming = row.node.deck } label: { Label("名前を変更", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) { deleting = row.node.deck } label: { Label("削除", systemImage: "trash") }
                    }
                }
            } footer: {
                if !model.isEmpty {
                    Text("上位のデッキ（セット）を選ぶと、その下のデッキをまとめて学習できます。長押しでオプション・名前の変更・削除。")
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            model.refreshCounts()
            model.sync.requestSync(force: true)
        }
        .sheet(item: $optionsDeck) { deck in
            DeckOptionsView(deckID: deck.id)
        }
        .alert("デッキ名を変更", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名前（「::」で階層）", text: $newName)
            Button("キャンセル", role: .cancel) {}
            Button("変更") { if let r = renaming { model.renameDeck(r.id, to: newName) } }
        }
        .confirmationDialog("「\(deleting?.baseName ?? "")」を削除しますか？",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let d = deleting {
                    if let sel = selection, model.collectionHandle?.deckAndChildren(d.id).contains(sel.deckID) == true { selection = nil }
                    model.deleteDeck(d.id)
                }
            }
        } message: {
            Text(model.sync.isConfigured
                 ? "下位のデッキとカード、学習履歴も削除されます。同期している他の端末からも削除されます。この操作は取り消せません。"
                 : "下位のデッキとカード、学習履歴も削除されます。この操作は取り消せません。")
        }
    }
}

struct DeckRow: View {
    var node: DeckNode
    var depth: Int
    var isCollapsed: Bool
    var onToggle: () -> Void
    @AppStorage(Settings.showRemainingKey) private var showRemaining = true

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(depth) * 16, height: 1)
            if node.children != nil {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isCollapsed ? "展開" : "折りたたむ")
            } else {
                Color.clear.frame(width: 24, height: 1)
            }
            Image(systemName: node.children != nil ? "square.stack.3d.up" : "rectangle.portrait")
                .foregroundStyle(.tint)
                .font(.callout)
            Text(node.deck.baseName)
                .lineLimit(2)
            Spacer(minLength: 4)
            if showRemaining {
                CountsLabel(counts: node.counts, compact: true)
            }
        }
        .contentShape(Rectangle())
    }
}

struct CountsLabel: View {
    var counts: DeckCounts
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 14) {
            count(counts.new, .blue)
            count(counts.learning, .red)
            count(counts.review, .green)
        }
        .font(compact ? .callout.monospacedDigit() : .title3.monospacedDigit().weight(.semibold))
    }

    @ViewBuilder
    private func count(_ n: Int, _ color: Color) -> some View {
        Text("\(n)")
            .foregroundStyle(n > 0 ? color : Color.secondary.opacity(0.6))
            .frame(minWidth: compact ? 22 : 36, alignment: .trailing)
    }
}
