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
                            Text(model.collections.isEmpty
                                 ? "Ankiのデッキ（.apkg / .colpkg）をインポートして学習を始めましょう。"
                                 : "左のリストから学習するデッキを選んでください。")
                        } actions: {
                            if model.collections.isEmpty {
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
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.ankiPackage, .ankiCollectionPackage, .ankiCollection, .zip, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls)
            case .failure(let error): model.alertMessage = error.localizedDescription
            }
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
    @State private var renaming: CollectionInfo?
    @State private var newName = ""
    @State private var deleting: CollectionInfo?

    var body: some View {
        List(selection: $selection) {
            if model.collections.isEmpty {
                Section {
                    Button { showImporter = true } label: {
                        Label("Ankiデッキをインポート", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text("AnkiWebの共有デッキやAnkiからエクスポートした .apkg / .colpkg を読み込めます。ファイルアプリや他のアプリの「共有」からも開けます。")
                }
            }
            ForEach(model.collections) { info in
                Section {
                    OutlineGroup(model.deckTrees[info.id] ?? [], children: \.children) { node in
                        DeckRow(node: node)
                            .tag(node.ref)
                    }
                } header: {
                    CollectionHeader(info: info, renaming: $renaming, newName: $newName, deleting: $deleting)
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            model.refreshCounts()
            model.sync.requestSync(force: true)
        }
        .alert("名前を変更", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名前", text: $newName)
            Button("キャンセル", role: .cancel) {}
            Button("変更") { if let r = renaming { model.rename(r.id, to: newName) } }
        }
        .confirmationDialog("このコレクションを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let d = deleting {
                    if selection?.collectionID == d.id { selection = nil }
                    model.delete(d.id)
                }
            }
        } message: {
            Text(model.sync.isConfigured
                 ? "学習履歴とメディアも削除されます。iCloud Driveで同期している他の端末からも削除されます。この操作は取り消せません。"
                 : "学習履歴とメディアも削除されます。この操作は取り消せません。")
        }
    }
}

struct CollectionHeader: View {
    @Environment(AppModel.self) private var model
    var info: CollectionInfo
    @Binding var renaming: CollectionInfo?
    @Binding var newName: String
    @Binding var deleting: CollectionInfo?

    var body: some View {
        HStack {
            Text(info.name).lineLimit(1)
            Spacer()
            Menu {
                Text("\(info.noteCount)ノート・\(info.cardCount)カード・メディア\(info.mediaCount)件")
                Button { newName = info.name; renaming = info } label: { Label("名前を変更", systemImage: "pencil") }
                Picker(selection: Binding(
                    get: { info.useFSRS.map { $0 ? 1 : 2 } ?? 0 },
                    set: { model.setFSRS(info.id, $0 == 0 ? nil : $0 == 1) })) {
                    Text("コレクションの設定に従う").tag(0)
                    Text("FSRS").tag(1)
                    Text("SM-2").tag(2)
                } label: {
                    Label("スケジューラ（現在: \(model.fsrsEnabled(info.id) ? "FSRS" : "SM-2")）", systemImage: "calendar")
                }
                .pickerStyle(.menu)
                Divider()
                Button(role: .destructive) { deleting = info } label: { Label("削除", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
                    .padding(.vertical, 4)
            }
            .textCase(nil)
        }
    }
}

struct DeckRow: View {
    var node: DeckNode
    @AppStorage(Settings.showRemainingKey) private var showRemaining = true

    var body: some View {
        HStack(spacing: 8) {
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
