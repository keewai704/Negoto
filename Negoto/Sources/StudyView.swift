import NegotoCore
import Observation
import SwiftUI

@MainActor
@Observable
final class StudyModel {
    let target: StudyTarget
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
    /// Bumped when the card's content changed (after editing), so the page is rebuilt.
    private(set) var contentVersion = 0
    let sessionStart = Date()
    var autoplayEnabled = true
    @ObservationIgnored private var shownAt = Date()
    /// Practice: remaining card ids (nothing is rescheduled).
    @ObservationIgnored private var practiceQueue: [Int64] = []

    var isPractice: Bool { if case .practice = target { return true } else { return false } }

    init(target: StudyTarget, collection: AnkiCollection) {
        self.target = target
        self.collection = collection
        let deckID: Int64
        switch target {
        case .deck(let ref): deckID = ref.deckID
        case .practice(_, let query):
            deckID = AnkiCollection.allDecksID
            practiceQueue = ((try? collection.searchCards(query, limit: 2000)) ?? []).shuffled()
        }
        self.session = StudySession(collection: collection, deckId: deckID)
        self.mediaFolder = collection.mediaFolder
        self.resolver = MediaResolver(folder: collection.mediaFolder)
        audio.configure(mediaFolder: collection.mediaFolder, resolver: resolver)
    }

    var hasTypeAnswer: Bool { rendered?.question.contains("[[type:") ?? false }

    var deckConfig: DeckConfig { collection.deckConfig(for: current?.card.deckId ?? AnkiCollection.allDecksID) }

    func loadNext() {
        audio.stop()
        typedAnswer = nil
        showingAnswer = false
        if isPractice {
            while let id = practiceQueue.first {
                if let card = try? collection.card(id: id) {
                    counts = DeckCounts(review: practiceQueue.count)
                    finished = false
                    show(card, kind: .review)
                    return
                }
                practiceQueue.removeFirst()
            }
            finish()
            return
        }
        guard let next = session.nextCard() else {
            finish()
            return
        }
        finished = false
        show(next.card, kind: next.kind)
    }

    private func finish() {
        current = nil
        rendered = nil
        finished = true
        counts = isPractice ? DeckCounts() : session.counts
        canUndo = !isPractice && session.canUndo
    }

    private func show(_ card: Card, kind: QueuedCard.Kind) {
        current = QueuedCard(card: card, kind: kind)
        if !isPractice {
            counts = session.counts
            canUndo = session.canUndo
        }
        guard let note = try? collection.note(id: card.noteId), let nt = collection.notetypes[note.notetypeId] else {
            rendered = RenderedCard(question: "<div class=negoto-template-error>このカードのノートまたはノートタイプが見つかりません。</div>",
                                    answer: "", questionAV: [], answerAV: [], css: "", isEmpty: false, cardOrd: card.ord,
                                    isCloze: false, fields: [:])
            labels = isPractice ? [:] : session.labels(for: card)
            return
        }
        self.note = note
        let deckName = collection.deckName(card.originalDeckId != 0 ? card.originalDeckId : card.deckId)
        var r = CardRenderer.render(card: card, note: note, notetype: nt, deckName: deckName, mediaExists: { [resolver] in resolver.exists($0) })
        if r.isEmpty {
            r.question += "<div class=negoto-template-error>このカードの表面は空です（ノートタイプのテンプレートを確認してください）。</div>"
        }
        rendered = r
        labels = isPractice ? [:] : session.labels(for: card)
        shownAt = Date()
        if autoplayEnabled && !deckConfig.disableAutoplay { audio.play(r.questionAV) }
    }

    /// Re-renders the current card (after its note was edited), keeping the side shown.
    func reloadCurrent() {
        guard let q = current, let card = try? collection.card(id: q.card.id) else { return }
        let answer = showingAnswer
        let auto = autoplayEnabled
        autoplayEnabled = false
        show(card, kind: q.kind)
        autoplayEnabled = auto
        showingAnswer = answer
        contentVersion += 1
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
        if isPractice {
            if !practiceQueue.isEmpty { practiceQueue.removeFirst() }
            if rating == .again {
                practiceQueue.insert(card.id, at: min(3, practiceQueue.count))
                againCount += 1
            }
            reviewedCount += 1
            loadNext()
            return
        }
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
        guard !isPractice, let card = try? session.undo() else { return }
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
        if isPractice, !practiceQueue.isEmpty { practiceQueue.removeFirst() }
        loadNext()
    }

    func buryCurrent() {
        guard let card = current?.card else { return }
        try? session.bury(card)
        if isPractice, !practiceQueue.isEmpty { practiceQueue.removeFirst() }
        loadNext()
    }

    func setFlag(_ flag: Int) {
        guard let q = current, let updated = try? session.setFlag(q.card, flag: flag) else { return }
        current = QueuedCard(card: updated, kind: q.kind)
    }
}

/// Full-screen study. The card is an opaque sheet (max 680pt wide); the header and controls float
/// over it as Liquid Glass. In landscape on phones the answer buttons move to the right (2×2).
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
    @AppStorage(Settings.hapticsKey) private var haptics = true
    @AppStorage(Settings.swipeKey) private var swipeToAnswer = false
    @AppStorage(Settings.twoButtonsKey) private var twoButtons = false
    let target: StudyTarget
    @State private var model: StudyModel?
    @State private var showInspector = false
    @State private var editingNote: EditorRequest?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task {
            if model == nil, let col = app.collectionHandle {
                let m = StudyModel(target: target, collection: col)
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

    private var isRegular: Bool { hSize == .regular }
    private var landscapePhone: Bool { vSize == .compact }

    @ViewBuilder
    private func content(_ model: StudyModel) -> some View {
        VStack(spacing: landscapePhone ? 6 : 12) {
            header(model)
            if model.finished {
                finishedView(model)
            } else if let rendered = model.rendered {
                if landscapePhone {
                    HStack(alignment: .top, spacing: 12) {
                        card(model, rendered)
                        sideControls(model)
                            .frame(width: 250)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                } else {
                    card(model, rendered)
                        .frame(maxWidth: Theme.cardMaxWidth)
                        .padding(.horizontal, 16)
                    bottomControls(model)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.reviewedCount) { _, _ in haptics }
        .inspector(isPresented: $showInspector) {
            CardInspector(model: model, onEdit: { edit(model) })
                .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingNote, onDismiss: { model.reloadCurrent() }) { request in
            NoteEditorSheet(request: request)
                .environment(app)
        }
        .background { shortcuts(model) }
    }

    private func edit(_ model: StudyModel) {
        if let id = model.note?.id { editingNote = .edit(noteID: id) }
    }

    private func card(_ model: StudyModel, _ rendered: RenderedCard) -> some View {
        CardWebView(html: page(model, rendered), mediaFolder: model.mediaFolder, readAccessRoot: app.libraryRoot,
                    zoom: zoom, controller: model.webController,
                    onTap: tapAction(model), onSwipe: swipeAction(model)) { message in
            model.handle(message)
        }
        .id(model.contentVersion)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tapAction(_ model: StudyModel) -> (() -> Void)? {
        if model.showingAnswer || model.hasTypeAnswer { return nil }
        return { Task { await model.reveal() } }
    }

    private func swipeAction(_ model: StudyModel) -> ((Bool) -> Void)? {
        guard swipeToAnswer && model.showingAnswer else { return nil }
        return { right in model.answer(right ? .good : .again) }
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
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 22, height: 22)
                }
                .circularGlassButtonStyle()
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("学習を終了")

                Spacer(minLength: 0)
                if !model.finished {
                    Group {
                        if case .practice(let title, _) = model.target {
                            HStack(spacing: 6) {
                                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("残り\(model.counts.review)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        } else {
                            CountsInline(counts: model.counts, highlight: model.showingAnswer ? nil : model.current?.kind)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .glassBackground(in: Capsule())
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 0)

                if !model.finished {
                    if isRegular {
                        GlassToolbarCluster {
                            ToolbarIcon(systemName: "arrow.uturn.backward", label: "元に戻す") { model.undo() }
                                .disabled(!model.canUndo)
                            flagMenu(model)
                            ToolbarIcon(systemName: showInspector ? "info.circle.fill" : "info.circle", label: "カード情報") {
                                showInspector.toggle()
                            }
                            moreMenu(model, includeAll: false)
                        }
                    } else {
                        moreMenu(model, includeAll: true)
                            .circularGlassButtonStyle()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, landscapePhone ? 2 : 6)
    }

    private func flagMenu(_ model: StudyModel) -> some View {
        Menu {
            ForEach(0..<8, id: \.self) { f in
                Button { model.setFlag(f) } label: {
                    Label(FlagInfo.name(f), systemImage: model.current?.card.userFlag == f ? "checkmark" : "flag")
                }
            }
        } label: {
            Image(systemName: (model.current?.card.userFlag ?? 0) > 0 ? "flag.fill" : "flag")
                .font(.body.weight(.medium))
                .foregroundStyle((model.current?.card.userFlag ?? 0) > 0 ? FlagInfo.color(model.current?.card.userFlag ?? 0) : .primary)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("フラグ")
    }

    private func moreMenu(_ model: StudyModel, includeAll: Bool) -> some View {
        Menu {
            if includeAll {
                Button { model.undo() } label: { Label("元に戻す", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Menu {
                    ForEach(0..<8, id: \.self) { f in
                        Button { model.setFlag(f) } label: {
                            Label(FlagInfo.name(f), systemImage: model.current?.card.userFlag == f ? "checkmark" : "flag")
                        }
                    }
                } label: { Label("フラグ", systemImage: "flag") }
                Button { showInspector = true } label: { Label("カード情報", systemImage: "info.circle") }
            }
            Button { edit(model) } label: { Label("ノートを編集", systemImage: "pencil") }
            Button { model.replay() } label: { Label("音声を再生", systemImage: "speaker.wave.2") }
            Divider()
            Button { model.buryCurrent() } label: { Label("今日は表示しない（延期）", systemImage: "moon.zzz") }
            Button(role: .destructive) { model.suspendCurrent() } label: { Label("カードを保留", systemImage: "pause.circle") }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: includeAll ? 22 : 36, height: includeAll ? 22 : 36)
        }
        .accessibilityLabel("その他")
    }

    // MARK: Controls

    private var visibleRatings: [Rating] { twoButtons ? [.again, .good] : Rating.allCases }

    private func bottomControls(_ model: StudyModel) -> some View {
        VStack(spacing: 8) {
            if !model.showingAnswer {
                Button { Task { await model.reveal() } } label: { Text("答えを表示") }
                    .buttonStyle(AccentButtonStyle(height: 50))
                    .frame(maxWidth: Theme.answerBarMaxWidth)
                Text(isRegular ? "スペース：答えを表示／普通 ・ ⌘Z：取り消し ・ ⌘E：編集" : "カードをタップしても表示できます")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(visibleRatings, id: \.self) { rating in
                        VStack(spacing: 6) {
                            ratingButton(model, rating)
                            if isRegular {
                                Text("\(rating.rawValue)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
                            }
                        }
                        // Extra room between "again" and the rest, so it isn't hit by mistake.
                        .padding(.trailing, rating == .again ? 10 : 0)
                    }
                }
                .frame(maxWidth: Theme.answerBarMaxWidth)
                if isRegular {
                    Text("1〜4キー／スペースで回答")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: model.showingAnswer)
    }

    /// Landscape phone: the controls sit to the right of the card, ratings as a 2×2 grid.
    private func sideControls(_ model: StudyModel) -> some View {
        VStack(spacing: 8) {
            if !model.showingAnswer {
                Spacer()
                Button { Task { await model.reveal() } } label: { Text("答えを表示") }
                    .buttonStyle(AccentButtonStyle(height: 50))
            } else {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        ratingButton(model, .again)
                        if !twoButtons { ratingButton(model, .hard) }
                    }
                    GridRow {
                        ratingButton(model, .good)
                        if !twoButtons { ratingButton(model, .easy) }
                    }
                }
                Spacer()
            }
        }
    }

    private func ratingButton(_ model: StudyModel, _ rating: Rating) -> some View {
        let color = Theme.color(for: rating)
        let interval = model.labels[rating] ?? ""
        return Button {
            model.answer(rating)
        } label: {
            VStack(spacing: 1) {
                if showIntervals && !interval.isEmpty {
                    Text(interval)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .opacity(0.85)
                }
                Text(Theme.title(for: rating))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.background(for: rating), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Theme.title(for: rating)) \(interval)")
    }

    /// Keyboard: Space/Return reveal then answer "Good", 1–4 answer, ⌘Z undo, ⌘E edit, R replay, I info.
    private func shortcuts(_ model: StudyModel) -> some View {
        Group {
            Button("") {
                if model.showingAnswer { model.answer(.good) } else { Task { await model.reveal() } }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.hasTypeAnswer && !model.showingAnswer)
            Button("") {
                if model.showingAnswer { model.answer(.good) } else { Task { await model.reveal() } }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(model.hasTypeAnswer && !model.showingAnswer)
            ForEach(Rating.allCases, id: \.self) { rating in
                Button("") { model.answer(rating) }
                    .keyboardShortcut(KeyEquivalent(Character(String(rating.rawValue))), modifiers: [])
                    .disabled(!model.showingAnswer)
            }
            Button("") { model.undo() }.keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo)
            Button("") { edit(model) }.keyboardShortcut("e", modifiers: .command)
            Button("") { model.replay() }.keyboardShortcut("r", modifiers: [])
            Button("") { showInspector.toggle() }.keyboardShortcut("i", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Finished

    private func finishedView(_ model: StudyModel) -> some View {
        let seconds = Int(Date().timeIntervalSince(model.sessionStart))
        let correct = model.reviewedCount == 0 ? nil : Double(model.reviewedCount - model.againCount) / Double(model.reviewedCount)
        return ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 32)
                VStack(spacing: 6) {
                    Text("おつかれさまでした").font(.title.weight(.bold))
                    Text(model.reviewedCount > 0 ? (model.isPractice ? "練習が終わりました。" : "今日の学習は完了です。")
                         : "今は学習するカードがありません。")
                        .foregroundStyle(.secondary)
                }
                if model.reviewedCount > 0 {
                    HStack(spacing: 10) {
                        summaryTile("\(model.reviewedCount)", "学習したカード")
                        summaryTile(Format.duration(seconds), "時間")
                        summaryTile(Format.percent(correct), "正答率")
                    }
                }
                VStack(spacing: 10) {
                    Button("閉じる") { dismiss() }
                        .buttonStyle(AccentButtonStyle(height: 48))
                        .keyboardShortcut(.defaultAction)
                    if model.canUndo {
                        Button { model.undo() } label: { Label("最後の解答を元に戻す", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(SoftButtonStyle(height: 44))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryTile(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .surface(padding: 14)
    }
}

/// Card details next to the card (iPad) or as a sheet (iPhone): next interval, history, tags.
struct CardInspector: View {
    let model: StudyModel
    var onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("カード情報").font(.title3.weight(.bold))
                if let card = model.current?.card {
                    VStack(spacing: 0) {
                        if !model.isPractice, let good = model.labels[.good] {
                            row("次回（普通）", good)
                        }
                        row("追加日", Date(timeIntervalSince1970: TimeInterval(card.noteId / 1000)).formatted(date: .numeric, time: .omitted))
                        row("復習回数", "\(card.reps)回")
                        row("ラプス", "\(card.lapses)回")
                        if let m = card.memoryState {
                            row("安定度", String(format: "%.1f日", m.stability))
                            row("難易度", String(format: "%.1f / 10", m.difficulty))
                        } else {
                            row("間隔", card.interval > 0 ? Format.interval(days: card.interval) : "–")
                            row("易しさ", card.factor > 0 ? "\(card.factor / 10)%" : "–")
                        }
                        row("デッキ", model.collection.deckName(card.deckId), last: true)
                    }
                    .background(Theme.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("履歴").font(.subheadline.weight(.semibold))
                        let history = model.collection.reviewHistory(cardID: card.id, limit: 12)
                        if history.isEmpty {
                            Text("まだ復習していません").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(history, id: \.id) { r in
                            HStack(spacing: 8) {
                                Circle().fill(Theme.color(for: Rating(rawValue: r.ease) ?? .good)).frame(width: 7, height: 7)
                                Text(Date(timeIntervalSince1970: TimeInterval(r.id / 1000)).formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                    .monospacedDigit()
                                Text(historyText(r))
                            }
                            .font(.footnote)
                        }
                    }

                    if let note = model.note, !note.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("タグ").font(.subheadline.weight(.semibold))
                            FlowTags(tags: note.tags)
                        }
                    }
                    Button(action: onEdit) { Label("ノートを編集", systemImage: "pencil").frame(maxWidth: .infinity) }
                        .buttonStyle(SoftButtonStyle(height: 40))
                }
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    private func historyText(_ r: RevlogEntry) -> String {
        let title = Theme.title(for: Rating(rawValue: r.ease) ?? .good)
        guard r.ease > 1 else { return title }
        let ivl = r.interval >= 0 ? "間隔\(Format.interval(days: r.interval))" : "間隔\(Scheduler.formatInterval(-r.interval))"
        return "\(title)・\(ivl)"
    }

    private func row(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.footnote)
                Spacer()
                Text(value).font(.footnote.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if !last { Divider().padding(.leading, 12) }
        }
    }
}

/// Tags as wrapping chips.
struct FlowTags: View {
    var tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
        }
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
