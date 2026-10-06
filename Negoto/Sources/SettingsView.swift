import NegotoCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Settings.appearanceKey) private var appearance = Settings.Appearance.system.rawValue
    @AppStorage(Settings.forceDarkCardsKey) private var forceDarkCards = true
    @AppStorage(Settings.autoplayKey) private var autoplay = true
    @AppStorage(Settings.cardZoomKey) private var zoom = 1.0
    @AppStorage(Settings.showIntervalsKey) private var showIntervals = true
    @AppStorage(Settings.showRemainingKey) private var showRemaining = true
    @AppStorage("syncAutomatically") private var syncAutomatically = true
    @State private var choosingFolder = false
    var showsDoneButton = true

    var body: some View {
        NavigationStack {
            Form {
                Section("表示") {
                    Picker("外観", selection: $appearance) {
                        ForEach(Settings.Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("ダークモードでカードも暗くする", isOn: $forceDarkCards)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("カードの文字サイズ")
                            Spacer()
                            Text("\(Int((zoom * 100).rounded()))%").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $zoom, in: 0.6...2.0, step: 0.05)
                    }
                    Toggle("ボタンに次の間隔を表示", isOn: $showIntervals)
                }
                Section {
                    Toggle("音声を自動再生", isOn: $autoplay)
                } header: {
                    Text("音声")
                } footer: {
                    Text("デッキのオプションで自動再生が無効になっている場合は再生しません。")
                }
                Section {
                    Toggle("FSRSを使う", isOn: Binding(get: { app.fsrsEnabled }, set: { app.setFSRS($0) }))
                } header: {
                    Text("スケジューラ")
                } footer: {
                    Text("オフのときはAnkiの従来方式（SM-2）で次の復習日を決めます。デッキごとの細かい設定は、デッキ一覧でデッキを長押しして「学習オプション」から変更できます。")
                }
                syncSection
                Section {
                    LabeledContent("ノート数", value: "\(app.collectionHandle?.noteCount ?? 0)")
                    LabeledContent("カード総数", value: "\(app.collectionHandle?.cardCount ?? 0)")
                } header: {
                    Text("ライブラリ")
                } footer: {
                    Text("学習データは端末内に保存されます。ファイルアプリの「Negoto」フォルダから .apkg を置いて読み込むこともできます。")
                }
                Section("キーボードショートカット（iPad）") {
                    shortcut("解答を表示", "Space")
                    shortcut("もう一度 / 難しい / 正解 / 簡単", "1 / 2 / 3 / 4")
                    shortcut("音声を再生", "R")
                    shortcut("元に戻す", "⌘Z")
                    shortcut("インポート", "⌘O")
                }
                Section("このアプリについて") {
                    LabeledContent("バージョン", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"))")
                    Text("Negotoは Anki（.apkg / .colpkg / .anki2 / .anki21 / .anki21b）と互換性のある単語帳アプリです。Ankiのテンプレート・クローズ・画像オクルージョン・ふりがな・TTS・数式・FSRSに対応しています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("数式表示に MathJax（Apache License 2.0）、Ogg Vorbis再生に stb_vorbis（パブリックドメイン）、ZIP展開に ZIPFoundation（MIT）、zstd（BSD）を使用しています。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(showsDoneButton ? .inline : .large)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
                }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        let sync = app.sync
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
                        Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath.icloud")
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
                 ? "デッキ（メディアを含む）と学習の進み具合が、同じApple IDの端末間で同期されます。iCloud Driveの「Negoto」フォルダに保存されます。同じカードを複数の端末で学習した場合は、後から学習した方の状態が残ります。デッキは1台の端末でだけインポートしてください。"
                 : "iCloud Driveに同期用のフォルダ（例:「Negoto」）を作り、すべての端末で同じフォルダを選んでください。デッキ（メディアを含む）と学習の進み具合が端末間で同期されます。同じカードを複数の端末で学習した場合は、後から学習した方の状態が残ります。デッキは1台の端末でだけインポートしてください。")
        }
        .sheet(isPresented: $choosingFolder) {
            DocumentPicker(contentTypes: [.folder], allowsMultipleSelection: false, asCopy: false) { urls in
                if let url = urls.first { sync.chooseFolder(url) }
            }
            .ignoresSafeArea()
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
                    Label("利用可能", systemImage: "checkmark.icloud").foregroundStyle(.green)
                } else {
                    Label(sync.containerChecked ? "利用不可" : "確認中", systemImage: "icloud.slash").foregroundStyle(.secondary)
                }
            }
            if let reason = sync.containerUnavailableReason, sync.containerChecked {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) { Text(keys).font(.callout.monospaced()) }
    }
}
