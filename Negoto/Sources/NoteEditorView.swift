import NegotoCore
import Observation
import PhotosUI
import SwiftUI
import UIKit

/// Editing state of one note (new or existing).
@MainActor
@Observable
final class NoteEditorModel {
    let app: AppModel
    private(set) var noteID: Int64?
    var notetypeID: Int64 = 0
    var deckID: Int64 = 1
    /// Field contents as edited (HTML, with line breaks as "\n").
    var fields: [String] = []
    var tags: [String] = []
    var newTag = ""
    var status: String?
    /// Shown inside the editor (the app-level alert can't appear over a sheet).
    var errorMessage: String?
    private(set) var savedSnapshot: [String] = []
    private(set) var cardIDs: [Int64] = []

    init(app: AppModel) {
        self.app = app
    }

    var collection: AnkiCollection? { app.collectionHandle }
    var notetype: Notetype? { collection?.notetypes[notetypeID] }
    var fieldNames: [String] { notetype?.fieldNames ?? [] }
    var isNew: Bool { noteID == nil }

    var notetypes: [Notetype] {
        (collection?.notetypes.values.map { $0 } ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var decks: [Deck] { collection?.sortedDecks.filter { !$0.isFiltered } ?? [] }

    func prepareNew(deckID preferred: Int64?) {
        noteID = nil
        cardIDs = []
        let types = notetypes
        if let last = app.lastNotetypeID, collection?.notetypes[last] != nil {
            notetypeID = last
        } else {
            notetypeID = (types.first { $0.name.hasPrefix("Basic") || $0.name.hasPrefix("基本") } ?? types.first)?.id ?? 0
        }
        if let preferred, collection?.decks[preferred] != nil {
            deckID = preferred
        } else if let last = app.lastDeckID, collection?.decks[last] != nil {
            deckID = last
        } else {
            deckID = decks.first { $0.id != 1 }?.id ?? 1
        }
        resizeFields()
        fields = fields.map { _ in "" }
        savedSnapshot = fields
    }

    func load(noteID id: Int64) {
        guard let col = collection, let note = try? col.note(id: id) else { return }
        noteID = id
        notetypeID = note.notetypeId
        fields = note.fields.map(Self.editable)
        resizeFields()
        tags = note.tags
        cardIDs = ((try? col.db.query("SELECT id FROM cards WHERE nid = ? ORDER BY ord", [id])) ?? []).map { $0[0].int64 }
        if let first = cardIDs.first, let card = try? col.card(id: first) {
            deckID = card.originalDeckId != 0 ? card.originalDeckId : card.deckId
        }
        savedSnapshot = fields
        status = nil
    }

    func resizeFields() {
        let n = fieldNames.count
        if fields.count < n { fields += Array(repeating: "", count: n - fields.count) }
        if fields.count > n && n > 0 { fields = Array(fields.prefix(n)) }
    }

    var hasChanges: Bool { fields != savedSnapshot }

    var htmlFields: [String] { fields.map(Self.html) }

    /// Adds the note (keeping the editor open for the next one) or saves the existing note.
    @discardableResult
    func save() -> Bool {
        commitTag()
        guard let col = collection else { return false }
        errorMessage = nil
        do {
            if let noteID {
                try col.updateNote(id: noteID, fields: htmlFields, tags: tags)
                let cards = ((try? col.db.query("SELECT id FROM cards WHERE nid = ?", [noteID])) ?? []).map { $0[0].int64 }
                try col.moveCards(cards, toDeck: deckID)
                savedSnapshot = fields
                status = "自動保存済み"
            } else {
                try col.addNote(notetypeId: notetypeID, deckId: deckID, fields: htmlFields, tags: tags)
                app.lastNotetypeID = notetypeID
                app.lastDeckID = deckID
                status = "追加しました"
                fields = fields.map { _ in "" }
                savedSnapshot = fields
            }
        } catch {
            status = nil
            errorMessage = error.localizedDescription
            return false
        }
        app.refreshCounts()
        app.sync.requestSync()
        return true
    }

    func delete() {
        guard let noteID else { return }
        app.edit { try $0.deleteNotes([noteID]) }
    }

    func commitTag() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        newTag = ""
        for part in Note.splitTags(t) where !tags.contains(part) { tags.append(part) }
    }

    /// Next unused cloze number across all fields.
    var nextClozeNumber: Int {
        let used = fields.reduce(into: Set<Int>()) { $0.formUnion(Cloze.ordinals(in: $1)) }
        return (used.max() ?? 0) + 1
    }

    /// Renders card `index` of the note being edited.
    func preview(cardIndex: Int, answer: Bool, dark: Bool) -> (html: String, folder: URL)? {
        guard let col = collection, let nt = notetype else { return nil }
        let note = Note(id: noteID ?? 0, guid: "", notetypeId: notetypeID, mod: 0, tags: tags, fields: htmlFields)
        let ords = col.cardOrdinals(notetype: nt, fields: htmlFields)
        let ord = ords.isEmpty ? 0 : ords[min(cardIndex, ords.count - 1)]
        let card = Card(id: 0, noteId: note.id, deckId: deckID, ord: ord, mod: 0, usn: 0, type: 0, queue: 0, due: 0, interval: 0,
                        factor: 0, reps: 0, lapses: 0, left: 0, originalDue: 0, originalDeckId: 0, flags: 0, data: "")
        let resolver = MediaResolver(folder: col.mediaFolder)
        let rendered = CardRenderer.render(card: card, note: note, notetype: nt, deckName: col.deckName(deckID),
                                           mediaExists: { resolver.exists($0) })
        let html = CardPage.document(card: rendered, side: answer ? .answer : .question, typedAnswer: nil, resolver: resolver,
                                     options: .init(nightMode: dark, forceDarkCards: true,
                                                    isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                                    supportBaseURL: app.supportDirectory.absoluteString))
        return (html, col.mediaFolder)
    }

    var previewCardCount: Int {
        guard let col = collection, let nt = notetype else { return 1 }
        return max(1, col.cardOrdinals(notetype: nt, fields: htmlFields).count)
    }

    private static let breakRegex = try! NSRegularExpression(pattern: "<br\\s*/?>", options: .caseInsensitive)

    static func editable(_ html: String) -> String {
        HTMLText.replace(breakRegex, in: html, with: "\n")
    }

    static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
    }
}

/// Tracks the field being edited so the formatting bar can act on its selection.
@MainActor
final class FieldFocus {
    weak var textView: UITextView?
    var index: Int?

    /// Wraps the selection (or inserts at the cursor) in `prefix`…`suffix`.
    func wrap(_ prefix: String, _ suffix: String, in model: NoteEditorModel) {
        guard let tv = textView, let index, index < model.fields.count else { return }
        let ns = tv.text as NSString
        let range = tv.selectedRange
        let selected = ns.substring(with: range)
        let replacement = prefix + selected + suffix
        tv.text = ns.replacingCharacters(in: range, with: replacement)
        tv.selectedRange = NSRange(location: range.location + (prefix as NSString).length + (selected as NSString).length, length: 0)
        model.fields[index] = tv.text
    }

    func insert(_ text: String, in model: NoteEditorModel) { wrap(text, "", in: model) }
}

/// Formatting commands for the field being edited (keyboard accessory bar and hardware shortcuts).
struct FormatActions {
    var bold: () -> Void
    var italic: () -> Void
    var underline: () -> Void
    var cloze: () -> Void
    var image: () -> Void
    var heading: () -> Void
}

/// The sections of a note editor (inside a Form): note type & deck, one section per field, tags.
struct NoteEditorSections: View {
    @Bindable var model: NoteEditorModel
    let focus: FieldFocus
    var onFieldChange: () -> Void = {}
    @State private var photo: PhotosPickerItem?
    @State private var choosingPhoto = false
    @FocusState private var tagFieldFocused: Bool

    var actions: FormatActions {
        FormatActions(
            bold: { wrap("<b>", "</b>") },
            italic: { wrap("<i>", "</i>") },
            underline: { wrap("<u>", "</u>") },
            cloze: { wrap("{{c\(model.nextClozeNumber)::", "}}") },
            image: { choosingPhoto = true },
            heading: { wrap("<span style=\"font-size: 1.5em\">", "</span>") }
        )
    }

    private func wrap(_ prefix: String, _ suffix: String) {
        focus.wrap(prefix, suffix, in: model)
        onFieldChange()
    }

    var body: some View {
        Section {
            Picker("ノートタイプ", selection: $model.notetypeID) {
                ForEach(model.notetypes) { Text($0.name).tag($0.id) }
            }
            .disabled(!model.isNew)
            Picker("デッキ", selection: $model.deckID) {
                ForEach(model.decks) { d in
                    Text(String(repeating: "　", count: d.depth) + d.baseName).tag(d.id)
                }
            }
        }
        .onChange(of: model.notetypeID) { _, _ in model.resizeFields() }

        ForEach(Array(model.fieldNames.enumerated()), id: \.offset) { index, name in
            Section(name) {
                FieldTextView(text: Binding(get: { index < model.fields.count ? model.fields[index] : "" },
                                            set: { value in
                                                guard index < model.fields.count else { return }
                                                model.fields[index] = value
                                                onFieldChange()
                                            }),
                              actions: actions,
                              clozeTitle: "[…]",
                              onFocus: { tv in
                                  focus.textView = tv
                                  focus.index = index
                              })
                    .frame(minHeight: 32)
                    .accessibilityLabel(name)
            }
        }

        Section("タグ") {
            if !model.tags.isEmpty {
                FlowTags(tags: model.tags) { tag in
                    model.tags.removeAll { $0 == tag }
                    onFieldChange()
                }
                .padding(.vertical, 4)
            }
            TextField("タグを追加", text: $model.newTag)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($tagFieldFocused)
                .submitLabel(.done)
                .onSubmit {
                    model.commitTag()
                    onFieldChange()
                }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let name = model.app.storeMedia(data, fileExtension: "jpg") {
                    focus.insert("<img src=\"\(name)\">", in: model)
                    onFieldChange()
                }
                photo = nil
            }
        }
    }
}

/// Hardware keyboard shortcuts for formatting (⌘B, ⌘I, ⌘U, ⇧⌘C).
struct FormatShortcuts: View {
    var actions: FormatActions

    var body: some View {
        Group {
            Button("", action: actions.bold).keyboardShortcut("b", modifiers: .command)
            Button("", action: actions.italic).keyboardShortcut("i", modifiers: .command)
            Button("", action: actions.underline).keyboardShortcut("u", modifiers: .command)
            Button("", action: actions.cloze).keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// A growing UITextView (so formatting can work on its selection), with the formatting bar above the keyboard.
struct FieldTextView: UIViewRepresentable {
    @Binding var text: String
    var actions: FormatActions
    var clozeTitle: String
    var onFocus: (UITextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.autocapitalizationType = .none
        tv.delegate = context.coordinator
        tv.text = text
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.inputAccessoryView = context.coordinator.makeToolbar(clozeTitle: clozeTitle)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(24, size.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: FieldTextView
        weak var textView: UITextView?
        init(_ parent: FieldTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            self.textView = textView
            parent.onFocus(textView)
        }

        func makeToolbar(clozeTitle: String) -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            func item(_ symbol: String, _ label: String, _ action: Selector) -> UIBarButtonItem {
                let b = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
                b.accessibilityLabel = label
                return b
            }
            let clozeItem = UIBarButtonItem(title: clozeTitle, style: .plain, target: self, action: #selector(Coordinator.cloze))
            clozeItem.accessibilityLabel = "穴埋め"
            bar.items = [
                item("bold", "太字", #selector(Coordinator.bold)),
                item("italic", "斜体", #selector(Coordinator.italic)),
                item("underline", "下線", #selector(Coordinator.underline)),
                clozeItem,
                item("photo", "画像を挿入", #selector(Coordinator.image)),
                item("textformat.size", "大きな文字", #selector(Coordinator.heading)),
                UIBarButtonItem(systemItem: .flexibleSpace),
                item("keyboard.chevron.compact.down", "キーボードを閉じる", #selector(Coordinator.done)),
            ]
            bar.sizeToFit()
            return bar
        }

        @objc private func bold() { parent.actions.bold() }
        @objc private func italic() { parent.actions.italic() }
        @objc private func underline() { parent.actions.underline() }
        @objc private func cloze() { parent.actions.cloze() }
        @objc private func image() { parent.actions.image() }
        @objc private func heading() { parent.actions.heading() }
        @objc private func done() { textView?.resignFirstResponder() }
    }
}

/// Live preview of the card being edited (front / back), as a Form section.
struct NotePreviewSection: View {
    let model: NoteEditorModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var answer = false
    @State private var cardIndex = 0

    var body: some View {
        Section {
            HStack {
                Picker("面", selection: $answer) {
                    Text("表").tag(false)
                    Text("裏").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                Spacer()
                if model.previewCardCount > 1 {
                    Picker("カード", selection: $cardIndex) {
                        ForEach(0..<model.previewCardCount, id: \.self) { Text("カード\($0 + 1)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            if let preview = model.preview(cardIndex: cardIndex, answer: answer, dark: colorScheme == .dark) {
                CardWebView(html: preview.html, mediaFolder: preview.folder, readAccessRoot: model.app.libraryRoot)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("プレビュー")
            }
        } header: {
            Text("プレビュー")
        }
    }
}

/// Sheet for adding a card or editing a note.
struct NoteEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: EditorRequest
    @State private var model: NoteEditorModel?
    @State private var focus = FieldFocus()
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    form(model)
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard model == nil else { return }
            let m = NoteEditorModel(app: app)
            switch request {
            case .add(let deckID): m.prepareNew(deckID: deckID)
            case .edit(let noteID): m.load(noteID: noteID)
            }
            model = m
        }
    }

    private func form(_ model: NoteEditorModel) -> some View {
        let sections = NoteEditorSections(model: model, focus: focus, onFieldChange: { if model.isNew { model.status = nil } })
        return Form {
            sections
            NotePreviewSection(model: model)
            if !model.isNew {
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("ノートを削除", systemImage: "trash") }
                }
            }
        }
        .readableScrollMargins()
        .scrollDismissesKeyboard(.interactively)
        .background { FormatShortcuts(actions: sections.actions) }
        .safeAreaInset(edge: .bottom) {
            if let status = model.status, model.isNew {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.review)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.status)
        .navigationTitle(model.isNew ? "カードを追加" : "ノートを編集")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                CancelToolbarButton { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                ConfirmToolbarButton(title: model.isNew ? "追加" : "保存") {
                    if model.save() && !model.isNew { dismiss() }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .alert("保存できません", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("このノートを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                model.delete()
                dismiss()
            }
        } message: {
            Text("ノートのカード（\(model.cardIDs.count)枚）と学習の進み具合が削除されます。")
        }
    }
}

/// "Close" in a sheet: an ✕ on iOS 26, a text button before.
struct CancelToolbarButton: View {
    var action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .cancel, action: action) { Image(systemName: "xmark") }
                .accessibilityLabel("閉じる")
        } else {
            Button("キャンセル", action: action)
        }
    }
}

/// The confirming action of a sheet: a prominent ✓ on iOS 26, a bold text button before.
struct ConfirmToolbarButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) { Image(systemName: "checkmark") }
                .buttonStyle(.glassProminent)
                .accessibilityLabel(title)
        } else {
            Button(title, action: action).fontWeight(.semibold)
        }
    }
}
