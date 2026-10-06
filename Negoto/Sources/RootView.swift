import NegotoCore
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, Hashable {
    case home, decks, stats, settings
}

/// Tab-based shell: Home (today), Decks, Statistics, Settings. Studying is presented full screen
/// from anywhere so that the card has the whole window.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("selectedTab") private var tab: AppTab = .home
    @State private var showImporter = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            HomeView(showImporter: $showImporter, openDecks: { tab = .decks })
                .tabItem { Label("ホーム", systemImage: "moon.stars") }
                .tag(AppTab.home)
            DecksView(showImporter: $showImporter)
                .tabItem { Label("デッキ", systemImage: "square.stack") }
                .tag(AppTab.decks)
            StatsView()
                .tabItem { Label("統計", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.stats)
            SettingsView(showsDoneButton: false)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .modifier(AdaptiveTabStyle())
        .modifier(GlassTabBarModifier { TodayAccessory() })
        .fullScreenCover(item: $model.studyTarget) { ref in
            StudyView(ref: ref)
                .environment(model)
        }
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

struct ImportProgressView: View {
    var status: AppModel.ImportStatus

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.night)
                Text("読み込み中…").font(.headline)
                ProgressView(value: status.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                Text(status.filename).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(28)
            .glassBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

/// Toolbar status of iCloud sync (spinner while syncing, tap to sync now).
struct SyncToolbarButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sync.isConfigured {
            if model.sync.isSyncing {
                ProgressView()
            } else {
                Button { model.sync.requestSync(force: true) } label: {
                    Label("同期", systemImage: model.sync.lastError == nil ? "arrow.triangle.2.circlepath.icloud" : "exclamationmark.icloud")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

/// Shown above the tab bar (iOS 26): today's remaining cards and a one-tap start.
struct TodayAccessory: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let counts = model.totalCounts
        HStack(spacing: 12) {
            Image(systemName: counts.total > 0 ? "moon.stars.fill" : "checkmark.circle.fill")
                .foregroundStyle(counts.total > 0 ? Theme.moon : Theme.review)
            if counts.total > 0 {
                Text("今日の残り").font(.subheadline)
                DuePills(counts: counts, size: .small)
            } else {
                Text(model.isEmpty ? "デッキを読み込んで始めましょう" : "今日の学習は完了").font(.subheadline)
            }
            Spacer(minLength: 4)
            if counts.total > 0 {
                Button { model.startStudy(.all) } label: {
                    Image(systemName: "play.fill")
                }
                .accessibilityLabel("今日の学習を始める")
            }
        }
        .padding(.horizontal, 16)
    }
}
