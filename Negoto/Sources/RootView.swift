import NegotoCore
import SwiftUI
import UniformTypeIdentifiers

/// Follows the horizontal size class like Apple's apps: a tab bar in compact widths (iPhone, narrow
/// iPad windows) and a sidebar (NavigationSplitView) in regular widths. Studying is presented full screen.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showImporter = false
    @State private var newDeckName = ""
    @State private var creatingDeck = false
    @State private var renameText = ""

    var body: some View {
        @Bindable var model = model
        Group {
            if hSize == .regular {
                SplitShell(actions: actions)
            } else {
                TabShell(actions: actions)
            }
        }
        .background { GlobalShortcuts(actions: actions) }
        .fullScreenCover(item: $model.studyTarget) { target in
            StudyView(target: target)
                .environment(model)
        }
        .sheet(item: $model.editorRequest) { request in
            NoteEditorSheet(request: request)
                .environment(model)
        }
        .sheet(item: $model.deckOptionsTarget) { ref in
            DeckOptionsView(deckID: ref.deckID)
                .environment(model)
        }
        .sheet(item: $model.customStudyTarget) { ref in
            CustomStudySheet(deckID: ref.deckID)
                .environment(model)
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(contentTypes: [.ankiPackage, .ankiCollectionPackage, .ankiCollection, .zip, .data],
                           allowsMultipleSelection: true) { urls in
                model.importFiles(urls)
            }
            .ignoresSafeArea()
        }
        .alert("デッキを作成", isPresented: $creatingDeck) {
            TextField("名前（「::」で階層）", text: $newDeckName)
            Button("キャンセル", role: .cancel) {}
            Button("作成") { model.createDeck(named: newDeckName) }
        }
        .alert("デッキ名を変更", isPresented: Binding(get: { model.renamingDeckID != nil },
                                                set: { if !$0 { model.renamingDeckID = nil } })) {
            TextField("名前（「::」で階層）", text: $renameText)
            Button("キャンセル", role: .cancel) {}
            Button("変更") { if let id = model.renamingDeckID { model.renameDeck(id, to: renameText) } }
        }
        .onChange(of: model.renamingDeckID) { _, id in
            if let id { renameText = model.collectionHandle?.decks[id]?.name ?? "" }
        }
        .confirmationDialog("「\(model.deletingDeckID.flatMap { model.collectionHandle?.decks[$0]?.baseName } ?? "")」を削除しますか？",
                            isPresented: Binding(get: { model.deletingDeckID != nil }, set: { if !$0 { model.deletingDeckID = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                guard let id = model.deletingDeckID else { return }
                if let sel = model.selectedDeckID, model.collectionHandle?.deckAndChildren(id).contains(sel) == true {
                    model.selectedDeckID = nil
                }
                model.deleteDeck(id)
            }
        } message: {
            Text("下位のデッキとカード、学習履歴も削除されます。" + (model.sync.isConfigured ? "同期している他の端末からも削除されます。" : "") + "この操作は取り消せません。")
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

    private var actions: ShellActions {
        ShellActions(
            importFile: { showImporter = true },
            createDeck: { newDeckName = ""; creatingDeck = true }
        )
    }
}

/// Actions shared by toolbars in both layouts.
struct ShellActions {
    var importFile: () -> Void
    var createDeck: () -> Void
}

// MARK: - Tab bar (compact width)

struct TabShell: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions
    @State private var deckPath: [Int64] = []

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.section) {
            NavigationStack(path: $deckPath) {
                DeckListView(actions: actions)
                    .navigationDestination(for: Int64.self) { id in
                        DeckOverviewView(deckID: id, actions: actions)
                    }
            }
            .tabItem { Label("デッキ", systemImage: "rectangle.stack") }
            .tag(AppSection.decks)

            NavigationStack { BrowseScreen() }
                .tabItem { Label("ブラウズ", systemImage: "list.bullet") }
                .tag(AppSection.browse)

            NavigationStack { StatsView() }
                .tabItem { Label("統計", systemImage: "chart.bar.xaxis") }
                .tag(AppSection.stats)

            NavigationStack { SettingsView(actions: actions) }
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppSection.settings)
        }
        .modifier(MinimizingTabBar())
        .onAppear(perform: syncPath)
        .onChange(of: model.selectedDeckID) { _, _ in syncPath() }
        .onChange(of: deckPath) { _, path in model.selectedDeckID = path.last }
    }

    /// A deck chosen elsewhere (search, sidebar before a size change) is pushed onto the decks stack.
    private func syncPath() {
        if let id = model.selectedDeckID, deckPath.last != id, model.collectionHandle?.decks[id] != nil {
            deckPath = [id]
        }
    }
}

/// iOS 26: the floating tab bar shrinks while scrolling down.
struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

// MARK: - Sidebar (regular width)

enum SidebarItem: Hashable {
    case section(AppSection)
    case deck(Int64)
    case tag(String)
}

struct SplitShell: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var selection: Binding<SidebarItem?> {
        Binding(get: {
            switch model.section {
            case .decks:
                if let id = model.selectedDeckID { return .deck(id) }
                return .section(.decks)
            case .browse:
                if let tag = Self.tag(in: model.browseQuery) { return .tag(tag) }
                return .section(.browse)
            default:
                return .section(model.section)
            }
        }, set: { item in
            switch item {
            case .section(let s)?:
                if s == .decks { model.selectedDeckID = nil }
                if s == .browse, Self.tag(in: model.browseQuery) != nil { model.browseQuery = "" }
                model.section = s
            case .deck(let id)?:
                model.openDeck(id)
            case .tag(let t)?:
                model.openBrowse(query: "tag:\(t.contains(" ") ? "\"\(t)\"" : t)")
            case nil:
                break
            }
        })
    }

    /// The tag of a query that is exactly `tag:…` (selected from the sidebar).
    static func tag(in query: String) -> String? {
        guard query.hasPrefix("tag:"), !query.contains(" ") || query.hasPrefix("tag:\"") else { return nil }
        let t = String(query.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return t.isEmpty ? nil : t
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(selection: selection, actions: actions)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            NavigationStack {
                detail
            }
            .id(detailKey)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .decks:
            if let id = model.selectedDeckID, model.collectionHandle?.decks[id] != nil {
                DeckOverviewView(deckID: id, actions: actions)
            } else {
                DeckListView(actions: actions)
            }
        case .browse: BrowseScreen()
        case .stats: StatsView()
        case .settings: SettingsView(actions: actions)
        }
    }

    /// A new detail stack for every sidebar destination (pushed views don't leak between them).
    private var detailKey: String {
        switch model.section {
        case .decks: return "decks-\(model.selectedDeckID ?? 0)"
        default: return model.section.rawValue
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    var actions: ShellActions
    @State private var showDecks = true
    @State private var showTags = true
    @State private var search = ""

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("今日の学習", systemImage: "calendar")
                    .badge(model.totalCounts.total)
                    .tag(SidebarItem.section(.decks))
                Label("ブラウズ", systemImage: "list.bullet")
                    .badge(model.collectionHandle?.cardCount ?? 0)
                    .tag(SidebarItem.section(.browse))
                Label("統計", systemImage: "chart.bar.xaxis")
                    .tag(SidebarItem.section(.stats))
                Label("設定", systemImage: "gearshape")
                    .tag(SidebarItem.section(.settings))
            }
            if !model.deckTree.isEmpty {
                Section("デッキ", isExpanded: $showDecks) {
                    OutlineGroup(model.deckTree, children: \.children) { node in
                        Label {
                            Text(node.deck.baseName).lineLimit(1)
                        } icon: {
                            DeckDot(id: node.deck.id)
                        }
                        .badge(node.counts.total)
                        .tag(SidebarItem.deck(node.deck.id))
                        .contextMenu { DeckMenuItems(deck: node.deck) }
                    }
                }
            }
            if !model.tags.isEmpty {
                Section("タグ", isExpanded: $showTags) {
                    ForEach(model.tags.prefix(100), id: \.self) { tag in
                        Label(tag, systemImage: "tag").tag(SidebarItem.tag(tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Negoto")
        .searchable(text: $search, placement: .sidebar, prompt: "カードを検索")
        .onSubmit(of: .search) { model.openBrowse(query: search) }
        .refreshable { model.sync.requestSync(force: true) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SyncToolbarButton()
                AddMenu(actions: actions, deckID: model.selectedDeckID)
            }
        }
    }
}

// MARK: - Shared pieces

/// Everything that can be done with a deck (context menus, swipe actions and the deck's "…" menu).
struct DeckMenuItems: View {
    @Environment(AppModel.self) private var model
    let deck: Deck

    var body: some View {
        Button { model.startStudy(DeckRef(deckID: deck.id)) } label: { Label("学習する", systemImage: "play") }
        Button { model.customStudyTarget = DeckRef(deckID: deck.id) } label: { Label("カスタム学習", systemImage: "wand.and.stars") }
        Button { model.editorRequest = .add(deckID: deck.id) } label: { Label("カードを追加", systemImage: "plus.rectangle.on.rectangle") }
        Button { model.openBrowse(query: deckQuery(deck.name)) } label: { Label("カードを見る", systemImage: "list.bullet") }
        Divider()
        Button { model.deckOptionsTarget = DeckRef(deckID: deck.id) } label: { Label("オプション", systemImage: "gearshape") }
        Button { model.renamingDeckID = deck.id } label: { Label("名前を変更", systemImage: "pencil") }
        Button(role: .destructive) { model.deletingDeckID = deck.id } label: { Label("削除", systemImage: "trash") }
    }
}

struct ImportProgressView: View {
    var status: AppModel.ImportStatus

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                Text("読み込み中…").font(.headline)
                ProgressView(value: status.progress)
                    .frame(width: 220)
                Text(status.filename).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sync status / "sync now" (toolbar).
struct SyncToolbarButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sync.isSyncing {
            ProgressView()
        } else {
            Button { model.sync.requestSync(force: true) } label: {
                Image(systemName: model.sync.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.arrow.triangle.2.circlepath")
            }
            .disabled(!model.sync.isConfigured)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .accessibilityLabel("同期")
        }
    }
}

/// "+" menu: add a card, create a deck, import a file (⌘N / ⌘O are global shortcuts, see `GlobalShortcuts`).
struct AddMenu: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions
    var deckID: Int64?

    var body: some View {
        Menu {
            Button { model.editorRequest = .add(deckID: deckID) } label: { Label("カードを追加", systemImage: "plus.rectangle.on.rectangle") }
                .disabled(model.collectionHandle?.notetypes.isEmpty ?? true)
            Button(action: actions.createDeck) { Label("デッキを作成", systemImage: "folder.badge.plus") }
            Button(action: actions.importFile) { Label("ファイルを読み込む", systemImage: "tray.and.arrow.down") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("追加メニュー")
    }
}

/// App-wide keyboard shortcuts: ⌘N add a card, ⌘O import a file.
struct GlobalShortcuts: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions

    var body: some View {
        Group {
            Button("") { model.editorRequest = .add(deckID: model.selectedDeckID) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.collectionHandle?.notetypes.isEmpty ?? true)
            Button("", action: actions.importFile)
                .keyboardShortcut("o", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
