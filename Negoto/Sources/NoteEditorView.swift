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
            app.alertMessage = error.localizedDescription
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

/// The whole editing form: note type & deck, fields, tags, formatting bar.
struct NoteEditorForm: View {
    @Bindable var model: NoteEditorModel
    let focus: FieldFocus
    var onFieldChange: () -> Void = {}
    @State private var photo: PhotosPickerItem?
    @State private var focusedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Menu {
                    Picker("ノートタイプ", selection: $model.notetypeID) {
                        ForEach(model.notetypes) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    chip(title: "タイプ", value: model.notetype?.name ?? "")
                }
                .disabled(!model.isNew)
                Menu {
                    Picker("デッキ", selection: $model.deckID) {
                        ForEach(model.decks) { d in
                            Text(String(repeating: "　", count: d.depth) + d.baseName).tag(d.id)
                        }
                    }
                } label: {
                    chip(title: "デッキ", value: model.collection?.decks[model.deckID]?.baseName ?? "")
                }
                Spacer(minLength: 0)
            }

            ForEach(Array(model.fieldNames.enumerated()), id: \.offset) { index, name in
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                    FieldTextView(text: Binding(get: { index < model.fields.count ? model.fields[index] : "" },
                                                set: { value in
                                                    guard index < model.fields.count else { return }
                                                    model.fields[index] = value
                                                    onFieldChange()
                                                }),
                                  onFocus: { tv in
                                      focus.textView = tv
                                      focus.index = index
                                      focusedIndex = index
                                  })
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(Theme.input, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous)
                                .stroke(focusedIndex == index ? Theme.accent : Color.secondary.opacity(0.18), lineWidth: focusedIndex == index ? 1.5 : 1)
                        }
                }
            }

            formatBar
            tagsRow
        }
        .onChange(of: model.notetypeID) { _, _ in model.resizeFields() }
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

    private func chip(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.15)))
    }

    private var formatBar: some View {
        HStack(spacing: 0) {
            formatButton("bold", "太字") { focus.wrap("<b>", "</b>", in: model); onFieldChange() }
            formatButton("italic", "斜体") { focus.wrap("<i>", "</i>", in: model); onFieldChange() }
            formatButton("underline", "下線") { focus.wrap("<u>", "</u>", in: model); onFieldChange() }
            Button {
                focus.wrap("{{c\(model.nextClozeNumber)::", "}}", in: model)
                onFieldChange()
            } label: {
                Text("{{c\(model.nextClozeNumber)}}").font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("穴埋め")
            .keyboardShortcut("c", modifiers: [.command, .shift])
            PhotosPicker(selection: $photo, matching: .images) {
                Image(systemName: "photo").frame(maxWidth: .infinity, minHeight: 36)
            }
            .accessibilityLabel("画像を挿入")
            formatButton("textformat.size", "見出し") { focus.wrap("<span style=\"font-size: 1.5em\">", "</span>", in: model); onFieldChange() }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.12)))
    }

    private func formatButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var tagsRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.tags, id: \.self) { tag in
                        Button {
                            model.tags.removeAll { $0 == tag }
                            onFieldChange()
                        } label: {
                            HStack(spacing: 3) {
                                Text(tag)
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.accentSoft, in: Capsule())
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("タグ「\(tag)」を外す")
                    }
                    TextField("+ タグ", text: $model.newTag)
                        .font(.caption)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minWidth: 70)
                        .onSubmit {
                            model.commitTag()
                            onFieldChange()
                        }
                }
            }
        }
    }
}

/// A growing UITextView (so the formatting bar can work on its selection).
struct FieldTextView: UIViewRepresentable {
    @Binding var text: String
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
        init(_ parent: FieldTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocus(textView)
        }
    }
}

/// Live preview of the card being edited (front / back).
struct NotePreview: View {
    let model: NoteEditorModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var answer = false
    @State private var cardIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("プレビュー").font(.subheadline.weight(.semibold))
                Spacer()
                if model.previewCardCount > 1 {
                    Picker("カード", selection: $cardIndex) {
                        ForEach(0..<model.previewCardCount, id: \.self) { Text("カード\($0 + 1)").tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Picker("面", selection: $answer) {
                    Text("表").tag(false)
                    Text("裏").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            if let preview = model.preview(cardIndex: cardIndex, answer: answer, dark: colorScheme == .dark) {
                CardWebView(html: preview.html, mediaFolder: preview.folder, readAccessRoot: model.app.libraryRoot)
                    .frame(minHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous))
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.block, style: .continuous))
            }
        }
    }
}

/// Sheet for adding a card or editing a note.
struct NoteEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: EditorRequest
    @State private var model: NoteEditorModel?
    @State private var tab = 0
    @State private var focus = FieldFocus()
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    VStack(spacing: 0) {
                        Picker("表示", selection: $tab) {
                            Text("編集").tag(0)
                            Text("プレビュー").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        ScrollView {
                            Group {
                                if tab == 0 {
                                    NoteEditorForm(model: model, focus: focus)
                                } else {
                                    NotePreview(model: model)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        if let status = model.status, model.isNew {
                            Text(status)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.bottom, 8)
                        }
                    }
                    .background(Theme.background)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("閉じる")
                        }
                        ToolbarItem(placement: .principal) {
                            Text(model.isNew ? "カードを追加" : "ノートを編集").font(.headline)
                        }
                        if !model.isNew {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("ノートを削除")
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                if model.save() && !model.isNew { dismiss() }
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .modifier(ProminentToolbarButton())
                            .keyboardShortcut(.return, modifiers: .command)
                            .accessibilityLabel(model.isNew ? "追加" : "保存")
                        }
                    }
                    .confirmationDialog("このノートを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("削除", role: .destructive) {
                            model.delete()
                            dismiss()
                        }
                    } message: {
                        Text("ノートのカード（\(model.cardIDs.count)枚）と学習の進み具合が削除されます。")
                    }
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
}

/// The confirm button as prominent (accent) glass on iOS 26.
struct ProminentToolbarButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(Theme.accent)
        } else {
            content.fontWeight(.semibold)
        }
    }
}
