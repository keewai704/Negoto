import NegotoCore
import Observation
import SwiftUI

@MainActor
@Observable
final class StudyModel {
    let ref: DeckRef
    let collection: AnkiCollection
    let session: StudySession
    let resolver: MediaResolver
    let mediaFolder: URL
    let audio = AudioPlayer()
    let webController = CardWebController()

    private(set) var current: QueuedCard?
    private(set) var note: Note?
    private(set) var rendered: RenderedCard?
    private(set) var showingAnswer = false
    private(set) var typedAnswer: String?
    private(set) var labels: [Rating: String] = [:]
    private(set) var finished = false
    private(set) var reviewedCount = 0
    private(set) var counts = DeckCounts()
    private(set) var canUndo = false
    var autoplayEnabled = true
    @ObservationIgnored private var shownAt = Date()

    init(ref: DeckRef, collection: AnkiCollection) {
        self.ref = ref
        self.collection = collection
        self.session = StudySession(collection: collection, deckId: ref.deckID)
        self.mediaFolder = collection.mediaFolder
        self.resolver = MediaResolver(folder: collection.mediaFolder)
        audio.configure(mediaFolder: collection.mediaFolder, resolver: resolver)
    }

    var hasTypeAnswer: Bool { rendered?.question.contains("[[type:") ?? false }

    var deckConfig: DeckConfig { collection.deckConfig(for: current?.card.deckId ?? ref.deckID) }

    func loadNext() {
        audio.stop()
        typedAnswer = nil
        showingAnswer = false
        guard let next = session.nextCard() else {
            current = nil
            rendered = nil
            finished = true
            counts = session.counts
            canUndo = session.canUndo
            return
        }
        finished = false
        show(next.card, kind: next.kind)
    }

    private func show(_ card: Card, kind: QueuedCard.Kind) {
        current = QueuedCard(card: card, kind: kind)
        counts = session.counts
        canUndo = session.canUndo
        guard let note = try? collection.note(id: card.noteId), let nt = collection.notetypes[note.notetypeId] else {
            rendered = RenderedCard(question: "<div class=negoto-template-error>このカードのノートまたはノートタイプが見つかりません。</div>",
                                    answer: "", questionAV: [], answerAV: [], css: "", isEmpty: false, cardOrd: card.ord,
                                    isCloze: false, fields: [:])
            labels = session.labels(for: card)
            return
        }
        self.note = note
        let deckName = collection.deckName(card.originalDeckId != 0 ? card.originalDeckId : card.deckId)
        var r = CardRenderer.render(card: card, note: note, notetype: nt, deckName: deckName, mediaExists: { [resolver] in resolver.exists($0) })
        if r.isEmpty {
            r.question += "<div class=negoto-template-error>このカードの表面は空です（ノートタイプのテンプレートを確認してください）。</div>"
        }
        rendered = r
        labels = session.labels(for: card)
        shownAt = Date()
        if autoplayEnabled && !deckConfig.disableAutoplay { audio.play(r.questionAV) }
    }

    func reveal() async {
        guard rendered != nil, !showingAnswer else { return }
        if hasTypeAnswer { typedAnswer = await webController.typedAnswer() }
        showingAnswer = true
        audio.stop()
        if autoplayEnabled && !deckConfig.disableAutoplay, let r = rendered { audio.play(r.answerAV) }
    }

    func answer(_ rating: Rating) {
        guard let card = current?.card, showingAnswer else { return }
        let ms = Int(Date().timeIntervalSince(shownAt) * 1000)
        do {
            try session.answer(card, rating: rating, millisecondsTaken: ms)
            reviewedCount += 1
        } catch {
            print("answer failed: \(error)")
        }
        loadNext()
    }

    func undo() {
        guard let card = try? session.undo() else { return }
        reviewedCount = max(0, reviewedCount - 1)
        let kind: QueuedCard.Kind = card.cardType == .new ? .new : (card.cardType == .review ? .review : .learning)
        audio.stop()
        typedAnswer = nil
        showingAnswer = false
        finished = false
        show(card, kind: kind)
    }

    func replay() {
        guard let r = rendered else { return }
        if showingAnswer {
            audio.play(deckConfig.skipQuestionWhenReplayingAnswer ? r.answerAV : r.questionAV + r.answerAV)
        } else {
            audio.play(r.questionAV)
        }
    }

    func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "play":
            guard let r = rendered, let index = (message["index"] as? NSNumber)?.intValue else { return }
            let tags = (message["side"] as? String) == "a" ? r.answerAV : r.questionAV
            if index >= 0 && index < tags.count { audio.play([tags[index]]) }
        case "enter":
            Task { await reveal() }
        case "log":
            print("card js:", message["message"] ?? "")
        default:
            break
        }
    }

    func suspendCurrent() {
        guard let card = current?.card else { return }
        try? session.suspend(card)
        loadNext()
    }

    func buryCurrent() {
        guard let card = current?.card else { return }
        try? session.bury(card)
        loadNext()
    }

    func setFlag(_ flag: Int) {
        guard let q = current, let updated = try? session.setFlag(q.card, flag: flag) else { return }
        current = QueuedCard(card: updated, kind: q.kind)
    }
}

struct StudyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSize
    @AppStorage(Settings.forceDarkCardsKey) private var forceDarkCards = true
    @AppStorage(Settings.autoplayKey) private var autoplay = true
    @AppStorage(Settings.cardZoomKey) private var zoom = 1.0
    @AppStorage(Settings.showIntervalsKey) private var showIntervals = true
    let ref: DeckRef
    @State private var model: StudyModel?
    @State private var showInfo = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(app.deck(ref)?.baseName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil, let col = app.collection(ref.collectionID) {
                let m = StudyModel(ref: ref, collection: col)
                m.autoplayEnabled = autoplay
                model = m
                m.loadNext()
            }
        }
        .onDisappear {
            model?.audio.stop()
            app.refreshCounts(for: ref.collectionID)
            app.sync.requestSync()
        }
    }

    @ViewBuilder
    private func content(_ model: StudyModel) -> some View {
        VStack(spacing: 0) {
            if model.finished {
                finishedView(model)
            } else if let rendered = model.rendered {
                countsBar(model)
                CardWebView(html: page(model, rendered), mediaFolder: model.mediaFolder, readAccessRoot: app.libraryRoot,
                            zoom: zoom, controller: model.webController) { message in
                    model.handle(message)
                }
                .ignoresSafeArea(.container, edges: .horizontal)
                bottomBar(model)
            }
        }
        .toolbar { toolbar(model) }
        .sheet(isPresented: $showInfo) {
            if let card = model.current?.card {
                CardInfoView(collection: model.collection, cardID: card.id)
            }
        }
    }

    private func page(_ model: StudyModel, _ rendered: RenderedCard) -> String {
        CardPage.document(card: rendered, side: model.showingAnswer ? .answer : .question, typedAnswer: model.typedAnswer,
                          resolver: model.resolver,
                          options: .init(nightMode: colorScheme == .dark, forceDarkCards: forceDarkCards,
                                         isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                         supportBaseURL: app.supportDirectory.absoluteString,
                                         autoplayVideo: autoplay && !model.deckConfig.disableAutoplay))
    }

    private func countsBar(_ model: StudyModel) -> some View {
        let kind = model.current?.kind
        return HStack(spacing: 18) {
            countItem(model.counts.new, .blue, active: kind == .new)
            countItem(model.counts.learning, .red, active: kind == .learning)
            countItem(model.counts.review, .green, active: kind == .review)
            if let flag = model.current?.card.userFlag, flag > 0 {
                Image(systemName: "flag.fill").foregroundStyle(FlagInfo.color(flag))
            }
        }
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func countItem(_ n: Int, _ color: Color, active: Bool) -> some View {
        Text("\(n)")
            .foregroundStyle(color)
            .underline(active, color: color)
            .frame(minWidth: 28)
    }

    @ViewBuilder
    private func bottomBar(_ model: StudyModel) -> some View {
        let shortcutsEnabled = !model.hasTypeAnswer || model.showingAnswer
        VStack(spacing: 0) {
            Divider()
            Group {
                if !model.showingAnswer {
                    Button {
                        Task { await model.reveal() }
                    } label: {
                        Text("解答を表示")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .applyShortcut(shortcutsEnabled ? KeyEquivalent(" ") : nil)
                } else {
                    HStack(spacing: 8) {
                        ForEach(Rating.allCases, id: \.self) { rating in
                            answerButton(model, rating)
                        }
                    }
                    .background {
                        // Space / Return answer "Good", as in Anki.
                        Group {
                            Button("") { model.answer(.good) }.keyboardShortcut(.space, modifiers: [])
                            Button("") { model.answer(.good) }.keyboardShortcut(.return, modifiers: [])
                        }
                        .opacity(0)
                        .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .background(.bar)
    }

    private func answerButton(_ model: StudyModel, _ rating: Rating) -> some View {
        let (title, color): (String, Color) = {
            switch rating {
            case .again: return ("もう一度", .red)
            case .hard: return ("難しい", .orange)
            case .good: return ("正解", .green)
            case .easy: return ("簡単", .blue)
            }
        }()
        return Button {
            model.answer(rating)
        } label: {
            VStack(spacing: 2) {
                if showIntervals {
                    Text(model.labels[rating] ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(hSize == .compact ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .applyShortcut(KeyEquivalent(Character(String(rating.rawValue))))
        .accessibilityLabel("\(title) \(model.labels[rating] ?? "")")
    }

    @ToolbarContentBuilder
    private func toolbar(_ model: StudyModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { model.undo() } label: { Label("元に戻す", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button { model.replay() } label: { Label("音声を再生", systemImage: "speaker.wave.2") }
                .keyboardShortcut("r", modifiers: [])
                .disabled(model.rendered == nil)
            Menu {
                Menu {
                    ForEach(0..<8, id: \.self) { f in
                        Button { model.setFlag(f) } label: {
                            Label(FlagInfo.name(f), systemImage: model.current?.card.userFlag == f ? "checkmark" : "flag")
                        }
                    }
                } label: { Label("フラグ", systemImage: "flag") }
                Button { showInfo = true } label: { Label("カード情報", systemImage: "info.circle") }
                Divider()
                Button { model.buryCurrent() } label: { Label("今日は表示しない（延期）", systemImage: "moon.zzz") }
                Button(role: .destructive) { model.suspendCurrent() } label: { Label("カードを保留", systemImage: "pause.circle") }
            } label: {
                Label("その他", systemImage: "ellipsis.circle")
            }
            .disabled(model.current == nil)
        }
    }

    private func finishedView(_ model: StudyModel) -> some View {
        ContentUnavailableView {
            Label("おつかれさまでした！", systemImage: "checkmark.seal.fill")
        } description: {
            Text(model.reviewedCount > 0
                 ? "このセッションで\(model.reviewedCount)枚のカードを学習しました。今日の分は完了です。"
                 : "このデッキに今日学習するカードはありません。")
        } actions: {
            if model.canUndo {
                Button("最後の解答を元に戻す") { model.undo() }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func applyShortcut(_ key: KeyEquivalent?) -> some View {
        if let key { self.keyboardShortcut(key, modifiers: []) } else { self }
    }
}

enum FlagInfo {
    static func name(_ f: Int) -> String {
        ["なし", "赤", "オレンジ", "緑", "青", "ピンク", "水色", "紫"][max(0, min(7, f))]
    }

    static func color(_ f: Int) -> Color {
        [Color.secondary, .red, .orange, .green, .blue, .pink, .cyan, .purple][max(0, min(7, f))]
    }
}

struct CardInfoView: View {
    let collection: AnkiCollection
    let cardID: Int64
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let card = try? collection.card(id: cardID) {
                    Section("カード") {
                        row("追加日", Date(timeIntervalSince1970: TimeInterval(card.noteId / 1000)).formatted(date: .abbreviated, time: .omitted))
                        row("種類", ["新規", "学習中", "復習", "再学習"][max(0, min(3, card.type))])
                        row("間隔", card.interval > 0 ? Scheduler.formatInterval(card.interval * 86_400) : "-")
                        row("易しさ", card.factor > 0 ? "\(card.factor / 10)%" : "-")
                        row("復習回数", "\(card.reps)")
                        row("失敗回数", "\(card.lapses)")
                        if let m = card.memoryState {
                            row("安定性 (FSRS)", String(format: "%.1f日", m.stability))
                            row("難易度 (FSRS)", String(format: "%.0f%%", (m.difficulty - 1) / 9 * 100))
                        }
                        row("デッキ", collection.deckName(card.deckId))
                    }
                    Section("復習履歴") {
                        let logs = (try? collection.db.query("SELECT id, ease, ivl, type, time FROM revlog WHERE cid = ? ORDER BY id DESC LIMIT 100", [cardID])) ?? []
                        if logs.isEmpty { Text("まだ復習していません").foregroundStyle(.secondary) }
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                            HStack {
                                Text(Date(timeIntervalSince1970: TimeInterval(log["id"].int64 / 1000)).formatted(date: .numeric, time: .shortened))
                                Spacer()
                                Text(["", "もう一度", "難しい", "正解", "簡単"][max(0, min(4, log["ease"].int))])
                                    .foregroundStyle(log["ease"].int == 1 ? Color.red : Color.primary)
                                Text(log["ivl"].int >= 0 ? Scheduler.formatInterval(log["ivl"].int * 86_400) : Scheduler.formatInterval(-log["ivl"].int))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 50, alignment: .trailing)
                            }
                            .font(.callout.monospacedDigit())
                        }
                    }
                }
            }
            .navigationTitle("カード情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
