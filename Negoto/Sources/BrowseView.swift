import NegotoCore
import SwiftUI

struct BrowseRow: Identifiable, Hashable {
    var id: Int64
    var text: String
    var detail: String
    var queue: Int
    var flag: Int
}

struct BrowseView: View {
    @Environment(AppModel.self) private var app
    let ref: DeckRef
    @State private var query = ""
    @State private var rows: [BrowseRow] = []
    @State private var total = 0
    private let pageLimit = 1000

    var body: some View {
        List(rows) { row in
            NavigationLink {
                CardPreviewView(ref: ref, cardID: row.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.text.isEmpty ? "（空）" : row.text).lineLimit(2)
                        if row.flag > 0 { Image(systemName: "flag.fill").foregroundStyle(FlagInfo.color(row.flag)).font(.caption) }
                    }
                    Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .opacity(row.queue < 0 ? 0.5 : 1)
            }
        }
        .overlay {
            if rows.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "カードを検索")
        .navigationTitle("カード一覧")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(total > rows.count ? "\(total)枚中\(rows.count)枚を表示" : "\(rows.count)枚")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            load()
        }
    }

    private func load() {
        guard let col = app.collection(ref.collectionID) else { return }
        let decks = col.deckAndChildren(ref.deckID).map(String.init).joined(separator: ",")
        var sql = "FROM cards c JOIN notes n ON n.id = c.nid WHERE c.did IN (\(decks))"
        var args: [SQLBindable] = []
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            for term in q.split(separator: " ") {
                sql += " AND (n.flds LIKE ? ESCAPE '\\' OR n.tags LIKE ? ESCAPE '\\')"
                let escaped = term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
                args += ["%\(escaped)%", "%\(escaped)%"]
            }
        }
        total = (try? col.db.scalar("SELECT count() " + sql, args).int) ?? 0
        let today = col.timingToday().daysElapsed
        let result = (try? col.db.query("SELECT c.id, n.sfld, n.flds, n.mid, c.ord, c.type, c.queue, c.due, c.ivl, c.flags \(sql) ORDER BY n.id, c.ord LIMIT \(pageLimit)", args)) ?? []
        rows = result.map { r in
            let nt = col.notetypes[r[3].int64]
            let sortIdx = nt?.sortFieldIndex ?? 0
            let fields = Note.splitFields(r[2].string)
            let raw = sortIdx < fields.count ? fields[sortIdx] : r[1].string
            let text = HTMLText.strip(raw.replacingOccurrences(of: "<br>", with: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
            let template = nt?.isCloze == true ? "クローズ \(r[4].int + 1)" : (nt?.template(forCardOrd: r[4].int)?.name ?? "")
            var status: String
            switch r[6].int {
            case -1: status = "保留中"
            case -2, -3: status = "延期中"
            case 0: status = "新規"
            case 1, 3: status = "学習中"
            default:
                let days = r[7].int - today
                status = days <= 0 ? "復習: 今日" : "復習: \(days)日後"
            }
            return BrowseRow(id: r[0].int64, text: String(text.prefix(200)),
                             detail: [nt?.name ?? "", template, status].filter { !$0.isEmpty }.joined(separator: " · "),
                             queue: r[6].int, flag: r[9].int & 7)
        }
    }
}

struct CardPreviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Settings.forceDarkCardsKey) private var forceDarkCards = true
    @AppStorage(Settings.cardZoomKey) private var zoom = 1.0
    let ref: DeckRef
    let cardID: Int64
    @State private var showAnswer = false
    @State private var audio = AudioPlayer()

    var body: some View {
        Group {
            if let col = app.collection(ref.collectionID), let card = try? col.card(id: cardID),
               let note = try? col.note(id: card.noteId), let nt = col.notetypes[note.notetypeId] {
                let resolver = MediaResolver(folder: col.mediaFolder)
                let rendered = CardRenderer.render(card: card, note: note, notetype: nt, deckName: col.deckName(card.deckId),
                                                   mediaExists: { resolver.exists($0) })
                let html = CardPage.document(card: rendered, side: showAnswer ? .answer : .question, typedAnswer: nil,
                                             resolver: resolver,
                                             options: .init(nightMode: colorScheme == .dark, forceDarkCards: forceDarkCards,
                                                            isPad: UIDevice.current.userInterfaceIdiom == .pad,
                                                            supportBaseURL: app.supportDirectory.absoluteString))
                CardWebView(html: html, mediaFolder: col.mediaFolder, readAccessRoot: app.libraryRoot, zoom: zoom) { message in
                    guard message["type"] as? String == "play", let index = (message["index"] as? NSNumber)?.intValue else { return }
                    audio.configure(mediaFolder: col.mediaFolder, resolver: resolver)
                    let tags = (message["side"] as? String) == "a" ? rendered.answerAV : rendered.questionAV
                    if index >= 0 && index < tags.count { audio.play([tags[index]]) }
                }
            } else {
                ContentUnavailableView("カードが見つかりません", systemImage: "questionmark.square.dashed")
            }
        }
        .navigationTitle(showAnswer ? "裏面" : "表面")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("面", selection: $showAnswer) {
                    Text("表面").tag(false)
                    Text("裏面").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .onDisappear { audio.stop() }
    }
}
