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
    @State private var confirmDisconnect = false

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
                    Toggle("デッキ一覧に残り枚数を表示", isOn: $showRemaining)
                }
                Section {
                    Toggle("音声を自動再生", isOn: $autoplay)
                } header: {
                    Text("音声")
                } footer: {
                    Text("デッキのオプションで自動再生が無効になっている場合は再生しません。")
                }
                syncSection
                Section {
                    LabeledContent("コレクション数", value: "\(app.collections.count)")
                    LabeledContent("カード総数", value: "\(app.collections.reduce(0) { $0 + $1.cardCount })")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        let sync = app.sync
        Section {
            if let folder = sync.folderName {
                LabeledContent("同期フォルダ", value: folder)
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
                Button("同期フォルダを変更") { choosingFolder = true }
                Button("同期を解除", role: .destructive) { confirmDisconnect = true }
            } else {
                Button {
                    choosingFolder = true
                } label: {
                    Label("iCloud Driveのフォルダを選択", systemImage: "icloud")
                }
            }
            if let error = sync.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("iCloud Drive 同期")
        } footer: {
            Text("""
            iCloud Driveに同期用のフォルダ（例:「Negoto」）を作り、すべての端末で同じフォルダを選んでください。            デッキ（メディアを含む）と学習の進み具合が端末間で同期されます。同じカードを複数の端末で学習した場合は、            後から学習した方の状態が残ります。デッキは1台の端末でだけインポートしてください。
            """)
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { sync.chooseFolder(url) }
        }
        .confirmationDialog("同期を解除しますか？", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("解除", role: .destructive) { sync.disconnect() }
        } message: {
            Text("この端末のデッキと学習データはそのまま残ります。iCloud Drive上のデータも削除されません。")
        }
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) { Text(keys).font(.callout.monospaced()) }
    }
}
