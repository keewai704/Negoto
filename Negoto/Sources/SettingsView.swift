import NegotoCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    var actions: ShellActions
    @AppStorage(Settings.appearanceKey) private var appearance = Settings.Appearance.system.rawValue
    @AppStorage(Settings.forceDarkCardsKey) private var forceDarkCards = true
    @AppStorage(Settings.autoplayKey) private var autoplay = true
    @AppStorage(Settings.cardZoomKey) private var zoom = 1.0
    @AppStorage(Settings.showIntervalsKey) private var showIntervals = true
    @AppStorage(Settings.hapticsKey) private var haptics = true
    @AppStorage(Settings.swipeKey) private var swipeToAnswer = false
    @AppStorage(Settings.twoButtonsKey) private var twoButtons = false

    private var defaultPreset: DeckConfig { app.collectionHandle?.deckConfigs[1] ?? .default }

    var body: some View {
        Form {
            Section {
                NavigationLink { SyncSettingsView() } label: { accountRow }
            }

            Section {
                Picker(selection: presetBinding(\.newPerDay)) {
                    ForEach(options([0, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 200], current: defaultPreset.newPerDay), id: \.self) { Text("\($0)").tag($0) }
                } label: { iconLabel("1日の新規カード", "star.fill", .blue) }
                .pickerStyle(.menu)
                Picker(selection: presetBinding(\.reviewsPerDay)) {
                    ForEach(options([50, 100, 150, 200, 300, 500, 1000, 9999], current: defaultPreset.reviewsPerDay), id: \.self) { Text("\($0)").tag($0) }
                } label: { iconLabel("1日の最大復習数", "arrow.counterclockwise", .green) }
                .pickerStyle(.menu)
                Picker(selection: retentionBinding) {
                    ForEach([80, 85, 88, 90, 92, 94, 95, 97], id: \.self) { Text("\($0)%").tag($0) }
                } label: { iconLabel("目標保持率", "target", .purple) }
                .pickerStyle(.menu)
                Picker(selection: $twoButtons) {
                    Text("4ボタン").tag(false)
                    Text("2ボタン（もう一度・普通）").tag(true)
                } label: { iconLabel("回答ボタン", "hand.tap.fill", .red) }
                .pickerStyle(.menu)
                Toggle(isOn: Binding(get: { app.fsrsEnabled }, set: { app.setFSRS($0) })) { iconLabel("FSRSを使う", "wand.and.stars", .orange) }
            } header: {
                Text("学習")
            } footer: {
                Text("目標保持率を上げると記憶は定着しやすくなりますが、毎日の復習枚数が増えます。ここでの値は「Default」プリセットのものです。デッキごとの設定はデッキの「オプション」で変更できます。")
            }

            Section("学習画面") {
                Toggle(isOn: $showIntervals) { iconLabel("ボタンに次回間隔を表示", "clock.fill", .teal) }
                Toggle(isOn: $swipeToAnswer) { iconLabel("スワイプで回答（右: 普通・左: もう一度）", "hand.draw.fill", .indigo) }
                Toggle(isOn: $autoplay) { iconLabel("音声を自動再生", "speaker.wave.2.fill", .pink) }
                Toggle(isOn: $haptics) { iconLabel("ハプティクス", "iphone.radiowaves.left.and.right", .gray) }
            }

            Section("表示") {
                Picker(selection: $appearance) {
                    ForEach(Settings.Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                } label: { iconLabel("テーマ", "circle.lefthalf.filled", .blue) }
                .pickerStyle(.menu)
                Toggle(isOn: $forceDarkCards) { iconLabel("ダークモードでカードも暗くする", "moon.fill", .indigo) }
                VStack(alignment: .leading) {
                    LabeledContent("カードの文字サイズ", value: "\(Int((zoom * 100).rounded()))%")
                    Slider(value: $zoom, in: 0.6...2.0, step: 0.05)
                }
            }

            Section {
                Button(action: actions.importFile) { iconLabel("Ankiのファイルを読み込む", "tray.and.arrow.down.fill", .blue) }
                LabeledContent("ノート", value: Format.number(app.collectionHandle?.noteCount ?? 0))
                LabeledContent("カード", value: Format.number(app.collectionHandle?.cardCount ?? 0))
            } header: {
                Text("データ")
            } footer: {
                Text(".apkg / .colpkg / .anki2 に対応しています。ファイルアプリの「Negoto」フォルダに置いたファイルも自動で読み込みます。")
            }

            Section("キーボード（iPad）") {
                shortcut("答えを表示／普通", "Space")
                shortcut("もう一度・難しい・普通・簡単", "1 2 3 4")
                shortcut("取り消し", "⌘Z")
                shortcut("ノートを編集", "⌘E")
                shortcut("カード情報", "⌘I")
                shortcut("音声を再生", "R")
                shortcut("ノートをマーク", "*")
                shortcut("カードを追加", "⌘N")
                shortcut("ファイルを読み込む", "⌘O")
            }

            Section("このアプリについて") {
                LabeledContent("バージョン", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"))")
                Text("NegotoはAnkiと互換性のある単語帳アプリです。テンプレート・穴埋め・画像オクルージョン・ふりがな・読み上げ・数式・FSRSに対応しています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("MathJax（Apache License 2.0）、stb_vorbis（パブリックドメイン）、ZIPFoundation（MIT）、zstd（BSD）を使用しています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .readableScrollMargins()
        .navigationTitle("設定")
    }

    private var accountRow: some View {
        let sync = app.sync
        return HStack(spacing: 12) {
            SettingsIcon(systemName: "icloud.fill", color: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud 同期")
                Text(syncStatus(sync)).font(.footnote).foregroundStyle(sync.lastError == nil ? Color.secondary : Color.red)
            }
        }
    }

    private func iconLabel(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label { Text(title).foregroundStyle(.primary) } icon: { SettingsIcon(systemName: icon, color: color) }
    }

    private func syncStatus(_ sync: SyncController) -> String {
        if !sync.isConfigured { return "同期はオフです" }
        if sync.isSyncing { return "同期中…" }
        if sync.lastError != nil { return "同期できませんでした" }
        if let date = sync.lastSyncDate {
            return "同期済み・" + date.formatted(.relative(presentation: .named))
        }
        return sync.locationDescription
    }

    private func options(_ base: [Int], current: Int) -> [Int] {
        base.contains(current) ? base : (base + [current]).sorted()
    }

    private func presetBinding(_ key: WritableKeyPath<DeckConfig, Int>) -> Binding<Int> {
        Binding(get: { defaultPreset[keyPath: key] }, set: { value in
            var conf = defaultPreset
            conf[keyPath: key] = value
            app.edit { try $0.save(deckConfig: conf) }
        })
    }

    private var retentionBinding: Binding<Int> {
        Binding(get: { Int((defaultPreset.desiredRetention * 100).rounded()) }, set: { value in
            var conf = defaultPreset
            conf.desiredRetention = Double(value) / 100
            app.edit { try $0.save(deckConfig: conf) }
        })
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) { Text(keys).font(.callout.monospaced()) }
    }
}

/// iCloud sync and signing details.
struct SyncSettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("syncAutomatically") private var syncAutomatically = true
    @State private var choosingFolder = false

    var body: some View {
        let sync = app.sync
        Form {
            Section {
                Picker("同期方法", selection: Binding(get: { sync.mode }, set: { mode in
                    if mode == .folder && sync.folderName == nil { choosingFolder = true } else { sync.setMode(mode) }
                })) {
                    if sync.containerURL != nil {
                        Text("iCloud（自動）").tag(SyncMode.container)
                    }
                    Text(sync.folderName.map { "iCloud Driveのフォルダ（\($0)）" } ?? "iCloud Driveのフォルダを選択…").tag(SyncMode.folder)
                    Text("オフ").tag(SyncMode.off)
                }
                if sync.mode != .off {
                    LabeledContent("保存先", value: sync.locationDescription)
                    Toggle("自動で同期", isOn: $syncAutomatically)
                    Button {
                        sync.requestSync(force: true)
                    } label: {
                        HStack {
                            Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if sync.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(sync.isSyncing)
                    if let date = sync.lastSyncDate {
                        LabeledContent("最終同期", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let message = sync.lastMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if sync.mode == .folder {
                    Button("同期フォルダを変更") { choosingFolder = true }
                }
                if let error = sync.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("iCloud 同期")
            } footer: {
                Text(sync.containerURL != nil
                     ? "デッキ（メディアを含む）、追加・編集したカード、学習の進み具合が、同じApple IDの端末間で同期されます。同じカードを複数の端末で学習した場合は、後から学習した方の状態が残ります。"
                     : "iCloud Driveに同期用のフォルダ（例:「Negoto」）を作り、すべての端末で同じフォルダを選んでください。デッキ（メディアを含む）、追加・編集したカード、学習の進み具合が端末間で同期されます。")
            }

            Section("署名とiCloud") {
                LabeledContent("署名の種類", value: sync.signing.title)
                if let team = sync.signing.teamName {
                    LabeledContent("チーム", value: team)
                }
                if let exp = sync.signing.expirationDate {
                    LabeledContent("署名の有効期限", value: exp.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("iCloudコンテナ") {
                    if sync.containerURL != nil {
                        Label("利用可能", systemImage: "checkmark.icloud").foregroundStyle(Theme.accent)
                    } else {
                        Label(sync.containerChecked ? "利用不可" : "確認中", systemImage: "icloud.slash").foregroundStyle(.secondary)
                    }
                }
                if let reason = sync.containerUnavailableReason, sync.containerChecked {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .readableScrollMargins()
        .navigationTitle("iCloud 同期")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosingFolder) {
            DocumentPicker(contentTypes: [.folder], allowsMultipleSelection: false, asCopy: false) { urls in
                if let url = urls.first { sync.chooseFolder(url) }
            }
            .ignoresSafeArea()
        }
    }
}
