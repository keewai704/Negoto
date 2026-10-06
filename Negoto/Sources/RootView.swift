import NegotoCore
import SwiftUI
import UniformTypeIdentifiers

/// Chooses the layout from the window width:
/// Compact (< 600pt) and Medium (600–1023pt) use tabs (bottom on iPhone, top on iPad) with one or two columns;
/// Wide (≥ 1024pt) uses a sidebar + list + detail. Studying is presented full screen from anywhere.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showImporter = false
    @State private var layout: LayoutClass?
    @State private var newDeckName = ""
    @State private var creatingDeck = false

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let current = layout ?? LayoutClass.resolve(width: geo.size.width, previous: nil)
            Group {
                if current == .wide {
                    WideShell(actions: actions)
                } else {
                    TabShell(actions: actions)
                }
            }
            .onAppear { layout = LayoutClass.resolve(width: geo.size.width, previous: layout) }
            .onChange(of: geo.size.width) { _, w in
                let next = LayoutClass.resolve(width: w, previous: layout)
                if next != layout { layout = next }
            }
        }
        .ignoresSafeArea(.keyboard)
        .tint(Theme.accent)
        .fullScreenCover(item: $model.studyTarget) { target in
            StudyView(target: target)
                .environment(model)
        }
        .sheet(item: $model.editorRequest) { request in
            NoteEditorSheet(request: request)
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

// MARK: - Tabs (Compact / Medium)

struct TabShell: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions

    private var tab: Binding<AppSection> {
        Binding(get: { model.section == .today ? .decks : model.section }, set: { model.section = $0 })
    }

    var body: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: tab) {
                Tab("デッキ", systemImage: "rectangle.on.rectangle", value: AppSection.decks) {
                    DecksScreen(actions: actions)
                }
                Tab("ブラウズ", systemImage: "list.bullet", value: AppSection.browse) {
                    BrowseScreen()
                }
                Tab("統計", systemImage: "chart.bar", value: AppSection.stats) {
                    StatsView()
                }
                Tab("設定", systemImage: "slider.horizontal.3", value: AppSection.settings) {
                    SettingsView(actions: actions)
                }
                Tab(value: AppSection.search, role: .search) {
                    SearchScreen()
                }
            }
            .modifier(MinimizingTabBar())
        } else {
            TabView(selection: tab) {
                DecksScreen(actions: actions)
                    .tabItem { Label("デッキ", systemImage: "rectangle.on.rectangle") }
                    .tag(AppSection.decks)
                BrowseScreen()
                    .tabItem { Label("ブラウズ", systemImage: "list.bullet") }
                    .tag(AppSection.browse)
                StatsView()
                    .tabItem { Label("統計", systemImage: "chart.bar") }
                    .tag(AppSection.stats)
                SettingsView(actions: actions)
                    .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
                    .tag(AppSection.settings)
                SearchScreen()
                    .tabItem { Label("検索", systemImage: "magnifyingglass") }
                    .tag(AppSection.search)
            }
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

// MARK: - Sidebar (Wide)

enum SidebarItem: Hashable {
    case section(AppSection)
    case deck(Int64)
    case tag(String)
}

struct WideShell: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var sidebarSearch = ""

    private var selection: Binding<SidebarItem?> {
        Binding(get: {
            switch model.section {
            case .decks, .today:
                if model.section == .decks, let id = model.selectedDeckID { return .deck(id) }
                return .section(model.section)
            case .browse:
                if model.browseQuery.hasPrefix("tag:") { return .tag(String(model.browseQuery.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) }
                return .section(.browse)
            default:
                return .section(model.section)
            }
        }, set: { item in
            switch item {
            case .section(let s)?:
                if s == .decks || s == .today { model.selectedDeckID = nil }
                if s == .browse { model.browseQuery = "" }
                model.section = s
            case .deck(let id)?:
                model.section = .decks
                model.selectedDeckID = id
            case .tag(let t)?:
                model.openBrowse(query: "tag:\(t.contains(" ") ? "\"\(t)\"" : t)")
            case nil:
                break
            }
        })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(selection: selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
                .searchable(text: $sidebarSearch, placement: .sidebar, prompt: "検索")
                .onSubmit(of: .search) {
                    model.openBrowse(query: sidebarSearch)
                }
        } detail: {
            detail
                .environment(\.showSidebar, columns == .detailOnly ? { columns = .all } : nil)
                .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .today, .decks: DecksScreen(actions: actions, todayOnly: model.section == .today)
        case .browse: BrowseScreen()
        case .stats: StatsView()
        case .settings: SettingsView(actions: actions)
        case .search: SearchScreen()
        }
    }
}

private struct ShowSidebarKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Set when the sidebar is collapsed: shows a button to bring it back.
    var showSidebar: (() -> Void)? {
        get { self[ShowSidebarKey.self] }
        set { self[ShowSidebarKey.self] = newValue }
    }
}

/// Toolbar button that reopens a collapsed sidebar (wide layout only).
struct SidebarToggleItem: ToolbarContent {
    @Environment(\.showSidebar) private var showSidebar

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let showSidebar {
                Button(action: showSidebar) { Image(systemName: "sidebar.left") }
                    .accessibilityLabel("サイドバーを表示")
            }
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    @State private var showDecks = true
    @State private var showTags = true

    var body: some View {
        List(selection: $selection) {
            Section("ライブラリ") {
                row("今日", "clock", count: model.totalCounts.total).tag(SidebarItem.section(.today))
                row("すべてのデッキ", "rectangle.on.rectangle", count: nil).tag(SidebarItem.section(.decks))
                row("ブラウズ", "list.bullet", count: model.collectionHandle?.cardCount).tag(SidebarItem.section(.browse))
                row("統計", "chart.bar", count: nil).tag(SidebarItem.section(.stats))
                row("設定", "slider.horizontal.3", count: nil).tag(SidebarItem.section(.settings))
            }
            Section(isExpanded: $showDecks) {
                ForEach(flatDecks, id: \.node.id) { item in
                    HStack(spacing: 8) {
                        DeckDot(id: item.node.deck.id)
                        Text(item.node.deck.baseName).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(item.node.counts.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, CGFloat(item.depth) * 14)
                    .tag(SidebarItem.deck(item.node.deck.id))
                }
            } header: {
                Text("デッキ")
            }
            if !model.tags.isEmpty {
                Section(isExpanded: $showTags) {
                    ForEach(model.tags.prefix(60), id: \.self) { tag in
                        Label(tag, systemImage: "tag").tag(SidebarItem.tag(tag))
                    }
                } header: {
                    Text("タグ")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Negoto")
    }

    private var flatDecks: [(node: DeckNode, depth: Int)] {
        var out: [(DeckNode, Int)] = []
        func walk(_ nodes: [DeckNode], _ depth: Int) {
            for n in nodes {
                out.append((n, depth))
                if depth < 2, let kids = n.children { walk(kids, depth + 1) }
            }
        }
        walk(model.deckTree, 0)
        return out
    }

    private func row(_ title: String, _ icon: String, count: Int?) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let count, count > 0 {
                Text(Format.number(count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared pieces

struct ImportProgressView: View {
    var status: AppModel.ImportStatus

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                Text("読み込み中…").font(.headline)
                ProgressView(value: status.progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 220)
                Text(status.filename).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(28)
            .glassBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
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

/// "+" menu: add a card, create a deck, import a file.
struct AddMenu: View {
    @Environment(AppModel.self) private var model
    var actions: ShellActions
    var deckID: Int64?

    var body: some View {
        Menu {
            Button { model.editorRequest = .add(deckID: deckID) } label: { Label("カードを追加", systemImage: "plus.rectangle") }
                .disabled(model.collectionHandle?.notetypes.isEmpty ?? true)
            Button(action: actions.createDeck) { Label("デッキを作成", systemImage: "folder.badge.plus") }
            Button(action: actions.importFile) { Label("ファイルを読み込む", systemImage: "tray.and.arrow.down") }
        } label: {
            Image(systemName: "plus")
        } primaryAction: {
            if model.collectionHandle?.notetypes.isEmpty ?? true { actions.importFile() } else { model.editorRequest = .add(deckID: deckID) }
        }
        .accessibilityLabel("追加")
        .background {
            Button("") { model.editorRequest = .add(deckID: deckID) }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
            Button("", action: actions.importFile)
                .keyboardShortcut("o", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}
