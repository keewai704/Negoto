import NegotoCore
import SwiftUI

/// Per-deck study options (Anki's deck options: presets, daily limits, steps, intervals, burying…).
struct DeckOptionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let deckID: Int64

    enum Scope: Hashable { case thisDeck, allUsingPreset }

    @State private var loaded = false
    @State private var conf = DeckConfig.default
    @State private var presetID: Int64 = 1
    @State private var scope: Scope = .thisDeck
    @State private var overrideLimits = false
    @State private var deckNewLimit = 20
    @State private var deckReviewLimit = 200
    @State private var learnStepsText = ""
    @State private var relearnStepsText = ""
    @State private var stepsError: String?

    private var col: AnkiCollection? { app.collectionHandle }
    private var deck: Deck? { col?.decks[deckID] }
    private var sharingDecks: [Deck] { col?.decks(usingConfig: presetID).filter { $0.id != deckID } ?? [] }
    private var presets: [DeckConfig] { (col?.deckConfigs.values.map { $0 } ?? []).sorted { $0.name < $1.name } }

    var body: some View {
        NavigationStack {
            Form {
                presetSection
                limitsSection
                newCardsSection
                lapsesSection
                if app.fsrsEnabled { fsrsSection }
                buryingSection
                audioSection
                advancedSection
            }
            .readableScrollMargins()
            .navigationTitle(deck?.baseName ?? "オプション")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(stepsError != nil) }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Sections

    private var presetSection: some View {
        Section {
            Picker("プリセット", selection: Binding(get: { presetID }, set: { selectPreset($0) })) {
                ForEach(presets) { p in Text(p.name).tag(p.id) }
            }
            if !sharingDecks.isEmpty {
                Picker("変更の適用先", selection: $scope) {
                    Text("このデッキだけ").tag(Scope.thisDeck)
                    Text("同じプリセットの全デッキ（\(sharingDecks.count + 1)）").tag(Scope.allUsingPreset)
                }
                .pickerStyle(.inline)
            }
        } header: {
            Text("プリセット")
        } footer: {
            if !sharingDecks.isEmpty {
                Text(scope == .thisDeck
                     ? "このプリセットは他に\(sharingDecks.count)個のデッキ（\(sharingDecks.prefix(3).map(\.baseName).joined(separator: "、"))\(sharingDecks.count > 3 ? "…" : "")）でも使われています。保存すると、このデッキ専用のプリセットが作られます。"
                     : "同じプリセットを使うすべてのデッキに反映されます。")
            }
        }
    }

    private var limitsSection: some View {
        Section {
            Stepper(value: $conf.newPerDay, in: 0...9999, step: 5) { row("新規カード/日", "\(conf.newPerDay)") }
            Stepper(value: $conf.reviewsPerDay, in: 0...99999, step: 10) { row("最大復習数/日", "\(conf.reviewsPerDay)") }
            Toggle("このデッキだけ別の上限にする", isOn: $overrideLimits)
            if overrideLimits {
                Stepper(value: $deckNewLimit, in: 0...9999, step: 5) { row("  新規（このデッキ）", "\(deckNewLimit)") }
                Stepper(value: $deckReviewLimit, in: 0...99999, step: 10) { row("  復習（このデッキ）", "\(deckReviewLimit)") }
            }
            Picker("新規と復習の順序", selection: $conf.newMix) {
                Text("混ぜる").tag(DeckConfig.NewMix.mixWithReviews)
                Text("復習の後").tag(DeckConfig.NewMix.afterReviews)
                Text("復習の前").tag(DeckConfig.NewMix.beforeReviews)
            }
        } header: {
            Text("1日の上限")
        } footer: {
            Text("上位のデッキで学習するときは、上位のデッキの上限も適用されます。")
        }
    }

    private var newCardsSection: some View {
        Section {
            stepsField("学習ステップ", text: $learnStepsText)
            if !app.fsrsEnabled {
                Stepper(value: $conf.graduatingIntervalGood, in: 1...365) { row("卒業間隔", "\(conf.graduatingIntervalGood)日") }
                Stepper(value: $conf.graduatingIntervalEasy, in: 1...365) { row("簡単の間隔", "\(conf.graduatingIntervalEasy)日") }
            }
        } header: {
            Text("新規カード")
        } footer: {
            Text("ステップは空白区切りで「1m 10m 1h 1d」のように入力します（m=分, h=時間, d=日）。")
        }
    }

    private var lapsesSection: some View {
        Section("忘れたカード") {
            stepsField("再学習ステップ", text: $relearnStepsText)
            if !app.fsrsEnabled {
                Stepper(value: $conf.minimumLapseInterval, in: 1...365) { row("最小間隔", "\(conf.minimumLapseInterval)日") }
            }
            Stepper(value: $conf.leechThreshold, in: 1...99) { row("リーチ判定（失敗回数）", "\(conf.leechThreshold)") }
            Picker("リーチになったとき", selection: $conf.leechAction) {
                Text("タグを付ける").tag(DeckConfig.LeechAction.tagOnly)
                Text("保留にする").tag(DeckConfig.LeechAction.suspend)
            }
        }
    }

    private var fsrsSection: some View {
        Section {
            VStack(alignment: .leading) {
                row("目標保持率", "\(Int((conf.desiredRetention * 100).rounded()))%")
                Slider(value: $conf.desiredRetention, in: 0.70...0.99, step: 0.01)
            }
        } header: {
            Text("FSRS")
        } footer: {
            Text("高くすると復習の間隔が短くなり、覚えている割合が上がります（その分、復習の量が増えます）。")
        }
    }

    private var buryingSection: some View {
        Section {
            Toggle("新規カードの兄弟を延期", isOn: $conf.buryNew)
            Toggle("復習カードの兄弟を延期", isOn: $conf.buryReviews)
            Toggle("日をまたぐ学習カードの兄弟を延期", isOn: $conf.buryInterdayLearning)
        } header: {
            Text("兄弟カードの延期")
        } footer: {
            Text("同じノートから作られたカード（表→裏・裏→表など）を、同じ日に続けて出さないようにします。")
        }
    }

    private var audioSection: some View {
        Section("音声") {
            Toggle("音声を自動再生", isOn: Binding(get: { !conf.disableAutoplay }, set: { conf.disableAutoplay = !$0 }))
            Toggle("解答の再生時に問題の音声も流す", isOn: Binding(get: { !conf.skipQuestionWhenReplayingAnswer },
                                                         set: { conf.skipQuestionWhenReplayingAnswer = !$0 }))
            Stepper(value: $conf.capAnswerTimeToSecs, in: 10...600, step: 10) { row("回答時間の上限", "\(conf.capAnswerTimeToSecs)秒") }
        }
    }

    private var advancedSection: some View {
        Section {
            Stepper(value: $conf.maximumReviewInterval, in: 1...36500, step: 30) { row("最大間隔", "\(conf.maximumReviewInterval)日") }
            if !app.fsrsEnabled {
                decimalRow("初期の易しさ", value: $conf.initialEase, range: 1.31...5.0, step: 0.05, percent: true)
                decimalRow("簡単ボーナス", value: $conf.easyMultiplier, range: 1.0...5.0, step: 0.05, percent: true)
                decimalRow("間隔の修飾子", value: $conf.intervalMultiplier, range: 0.5...2.0, step: 0.05, percent: true)
                decimalRow("難しいの間隔", value: $conf.hardMultiplier, range: 0.5...1.5, step: 0.05, percent: true)
                decimalRow("忘れた後の新しい間隔", value: $conf.lapseMultiplier, range: 0.0...1.0, step: 0.05, percent: true)
            }
        } header: {
            Text("詳細")
        } footer: {
            Text(app.fsrsEnabled ? "FSRSを使っているため、易しさや間隔の倍率は使われません。" : "Ankiの「詳細」オプションと同じ意味です。")
        }
    }

    // MARK: Helpers

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func decimalRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, percent: Bool) -> some View {
        Stepper(value: value, in: range, step: step) {
            row(title, percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : String(format: "%.2f", value.wrappedValue))
        }
    }

    private func stepsField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                TextField("1m 10m", text: text)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: text.wrappedValue) { _, _ in validateSteps() }
            }
            if let stepsError { Text(stepsError).font(.caption).foregroundStyle(.red) }
        }
    }

    static func format(_ minutes: [Double]) -> String {
        minutes.map { m in
            if m >= 1440, (m / 1440).rounded() == m / 1440 { return "\(Int(m / 1440))d" }
            if m >= 60, (m / 60).rounded() == m / 60 { return "\(Int(m / 60))h" }
            if m < 1 { return "\(Int((m * 60).rounded()))s" }
            return m.rounded() == m ? "\(Int(m))m" : String(format: "%.1fm", m)
        }.joined(separator: " ")
    }

    static func parse(_ text: String) -> [Double]? {
        var out: [Double] = []
        for token in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," || $0 == "、" || $0 == "　" }) {
            var t = String(token)
            var mult = 1.0
            if let last = t.last, "smhd".contains(last) {
                t.removeLast()
                mult = ["s": 1.0 / 60, "m": 1, "h": 60, "d": 1440][String(last)] ?? 1
            }
            guard let v = Double(t), v > 0 else { return nil }
            out.append(v * mult)
        }
        return out
    }

    private func validateSteps() {
        stepsError = (Self.parse(learnStepsText) == nil || Self.parse(relearnStepsText) == nil)
            ? "ステップは「1m 10m 1d」のように入力してください" : nil
    }

    private func load() {
        guard !loaded, let col, let deck else { return }
        loaded = true
        conf = col.deckConfig(for: deck.id)
        presetID = conf.id
        overrideLimits = deck.newLimit != nil || deck.reviewLimit != nil
        deckNewLimit = deck.newLimit ?? conf.newPerDay
        deckReviewLimit = deck.reviewLimit ?? conf.reviewsPerDay
        learnStepsText = Self.format(conf.learnSteps)
        relearnStepsText = Self.format(conf.relearnSteps)
    }

    private func selectPreset(_ id: Int64) {
        guard let c = col?.deckConfigs[id] else { return }
        presetID = id
        conf = c
        learnStepsText = Self.format(c.learnSteps)
        relearnStepsText = Self.format(c.relearnSteps)
        scope = .thisDeck
    }

    private func save() {
        guard let col, let deck, let learn = Self.parse(learnStepsText), let relearn = Self.parse(relearnStepsText) else { return }
        conf.learnSteps = learn
        conf.relearnSteps = relearn
        do {
            if !sharingDecks.isEmpty && scope == .thisDeck {
                let own = try col.addDeckConfig(copying: conf, name: deck.baseName)
                try col.setDeckConfigID(deck: deck.id, configID: own.id)
            } else {
                try col.save(deckConfig: conf)
                if deck.configId != conf.id { try col.setDeckConfigID(deck: deck.id, configID: conf.id) }
            }
            try col.setDeckLimits(deck: deck.id, newLimit: overrideLimits ? deckNewLimit : nil,
                                  reviewLimit: overrideLimits ? deckReviewLimit : nil)
            app.optionsChanged()
            dismiss()
        } catch {
            app.alertMessage = "保存できませんでした: \(error.localizedDescription)"
        }
    }
}
