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
    private(set) var againCount = 0
    let sessionStart = Date()
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
            if rating == .again { againCount += 1 }
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

/// Full-screen study: slim progress header, the card, and large answer buttons.
struct StudyView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.dismiss) private var dismiss
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
        .background(Color(.systemBackground).ignoresSafeArea())
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
            app.refreshCounts()
            app.sync.requestSync()
        }
    }

    @Namespace private var glassSpace
    @State private var headerHeight: CGFloat = 60
    @State private var controlsHeight: CGFloat = 80

    /// The card fills the window; header and answer controls float above it as Liquid Glass.
    @ViewBuilder
    private func content(_ model: StudyModel) -> some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let landscapePhone = vSize == .compact
            ZStack(alignment: .top) {
                if model.finished {
                    finishedView(model)
                        .padding(.top, headerHeight)
                } else if let rendered = model.rendered {
                    CardWebView(html: page(model, rendered), mediaFolder: model.mediaFolder, readAccessRoot: app.libraryRoot,
                                zoom: zoom,
                                contentInsets: EdgeInsets(top: safe.top + headerHeight + 8, leading: 0,
                                                          bottom: landscapePhone ? safe.bottom + 12 : safe.bottom + controlsHeight + 16,
                                                          trailing: 0),
                                controller: model.webController) { message in
                        model.handle(message)
                    }
                    .padding(.trailing, landscapePhone ? 206 + safe.trailing : 0)
                    .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    header(model)
                        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
                        .onPreferenceChange(HeightKey.self) { headerHeight = $0 }
                    Spacer(minLength: 0)
                    if !model.finished && model.rendered != nil && !landscapePhone {
                        bottomControls(model)
                            .background(GeometryReader { g in Color.clear.preference(key: ControlsHeightKey.self, value: g.size.height) })
                            .onPreferenceChange(ControlsHeightKey.self) { controlsHeight = $0 }
                    }
                }
                if !model.finished && model.rendered != nil && landscapePhone {
                    HStack {
                        Spacer()
                        sideRail(model)
                    }
                    .padding(.top, headerHeight + 8)
                }
            }
        }
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

    // MARK: Header (floating glass)

    private func header(_ model: StudyModel) -> some View {
        let done = model.reviewedCount
        let total = done + model.counts.total
        return GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 22, height: 22)
                }
                .circularGlassButtonStyle()
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("学習を終了")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(app.displayName(ref)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if !model.finished { countsView(model) }
                    }
                    ProgressView(value: total == 0 ? 1 : Double(done) / Double(total))
                        .tint(Color.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassBackground(in: Capsule())

                if !model.finished { moreMenu(model) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, vSize == .compact ? 2 : 6)
        .padding(.bottom, 4)
    }

    private func countsView(_ model: StudyModel) -> some View {
        let kind = model.current?.kind
        return HStack(spacing: 6) {
            countItem(model.counts.new, Theme.new, active: kind == .new && !model.showingAnswer)
            countItem(model.counts.learning, Theme.learning, active: kind == .learning && !model.showingAnswer)
            countItem(model.counts.review, Theme.review, active: kind == .review && !model.showingAnswer)
            if let flag = model.current?.card.userFlag, flag > 0 {
                Image(systemName: "flag.fill").foregroundStyle(FlagInfo.color(flag)).font(.caption)
            }
        }
        .font(.footnote.weight(.semibold).monospacedDigit())
    }

    private func countItem(_ n: Int, _ color: Color, active: Bool) -> some View {
        Text("\(n)")
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(active ? color.opacity(0.18) : .clear, in: Capsule())
    }

    private func moreMenu(_ model: StudyModel) -> some View {
        Menu {
            Button { model.undo() } label: { Label("元に戻す", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            Button { model.replay() } label: { Label("音声を再生", systemImage: "speaker.wave.2") }
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
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 22, height: 22)
        }
        .circularGlassButtonStyle()
        .accessibilityLabel("その他")
        .background {
            // Keyboard shortcuts that live outside the menu.
            Group {
                Button("") { model.undo() }.keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo)
                Button("") { model.replay() }.keyboardShortcut("r", modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    // MARK: Answer controls (floating glass, morphing between "show answer" and the four ratings)

    private func bottomControls(_ model: StudyModel) -> some View {
        GlassGroup(spacing: 10) {
            if !model.showingAnswer {
                Button {
                    Task { await model.reveal() }
                } label: {
                    Label("解答を表示", systemImage: "eye").wideLabel(minHeight: 40)
                }
                .primaryActionStyle()
                .glassID("controls", in: glassSpace)
                .applyShortcut(!model.hasTypeAnswer ? KeyEquivalent(" ") : nil)
            } else {
                HStack(spacing: 8) {
                    ForEach(Rating.allCases, id: \.self) { rating in
                        ratingButton(model, rating)
                            .glassID(rating == .good ? "controls" : "rating\(rating.rawValue)", in: glassSpace)
                    }
                }
                .background { goodShortcuts(model) }
            }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.showingAnswer)
    }

    /// Answer controls as a floating column (landscape on phones).
    private func sideRail(_ model: StudyModel) -> some View {
        GlassGroup(spacing: 8) {
            VStack(spacing: 8) {
                if !model.showingAnswer {
                    Spacer()
                    Button {
                        Task { await model.reveal() }
                    } label: {
                        Label("解答を表示", systemImage: "eye").wideLabel(minHeight: 40)
                    }
                    .primaryActionStyle()
                    .glassID("controls", in: glassSpace)
                    .applyShortcut(!model.hasTypeAnswer ? KeyEquivalent(" ") : nil)
                } else {
                    ForEach(Rating.allCases.reversed(), id: \.self) { rating in
                        ratingButton(model, rating, fillHeight: true)
                            .glassID(rating == .good ? "controls" : "rating\(rating.rawValue)", in: glassSpace)
                    }
                    .background { goodShortcuts(model) }
                }
            }
        }
        .frame(width: 190)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.showingAnswer)
    }

    /// Space / Return answer "Good", as in Anki.
    private func goodShortcuts(_ model: StudyModel) -> some View {
        Group {
            Button("") { model.answer(.good) }.keyboardShortcut(.space, modifiers: [])
            Button("") { model.answer(.good) }.keyboardShortcut(.return, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func ratingButton(_ model: StudyModel, _ rating: Rating, fillHeight: Bool = false) -> some View {
        let color = Theme.color(for: rating)
        let title = Theme.title(for: rating)
        return Button {
            model.answer(rating)
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(hSize == .compact ? .subheadline.weight(.bold) : .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if showIntervals {
                    Text(model.labels[rating] ?? "")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .opacity(0.85)
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: fillHeight ? 44 : 60, maxHeight: fillHeight ? .infinity : nil)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous), tint: color.opacity(0.22), interactive: true)
        }
        .buttonStyle(.plain)
        .applyShortcut(KeyEquivalent(Character(String(rating.rawValue))))
        .accessibilityLabel("\(title) \(model.labels[rating] ?? "")")
    }

    // MARK: Finished

    private func finishedView(_ model: StudyModel) -> some View {
        let seconds = Int(Date().timeIntervalSince(model.sessionStart))
        let correct = model.reviewedCount == 0 ? nil : Double(model.reviewedCount - model.againCount) / Double(model.reviewedCount)
        return ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Theme.night).frame(width: 120, height: 120)
                    StarField().clipShape(Circle()).frame(width: 120, height: 120)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.moon)
                }
                .padding(.top, 40)
                VStack(spacing: 6) {
                    Text("おつかれさまでした").font(.title.weight(.bold))
                    Text(model.reviewedCount > 0 ? "このデッキの今日の学習は完了です。" : "このデッキに今日学習するカードはありません。")
                        .foregroundStyle(.secondary)
                }
                if model.reviewedCount > 0 {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        StatTile(icon: "rectangle.stack.fill", title: "学習したカード", value: "\(model.reviewedCount)", tint: Theme.new)
                        StatTile(icon: "clock.fill", title: "時間", value: Format.duration(seconds), tint: Theme.nightBottom)
                        StatTile(icon: "checkmark.seal.fill", title: "正答率", value: Format.percent(correct), tint: Theme.review)
                    }
                }
                VStack(spacing: 10) {
                    Button { dismiss() } label: { Text("閉じる").wideLabel() }
                        .primaryActionStyle()
                        .keyboardShortcut(.defaultAction)
                    if model.canUndo {
                        Button { model.undo() } label: { Label("最後の解答を元に戻す", systemImage: "arrow.uturn.backward").wideLabel(minHeight: 28) }
                            .secondaryActionStyle()
                    }
                }
            }
            .padding(20)
            .readableWidth(560)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ControlsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 80
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
