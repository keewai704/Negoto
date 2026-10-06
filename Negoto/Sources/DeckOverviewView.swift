import NegotoCore
import SwiftUI

struct DeckOverviewView: View {
    @Environment(AppModel.self) private var model
    var ref: DeckRef
    @Binding var path: NavigationPath

    var body: some View {
        let deck = model.deck(ref)
        let node = findNode()
        let counts = node?.counts ?? DeckCounts()
        let col = model.collection(ref.collectionID)
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(deck?.baseName ?? "")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let parent = deck?.parentName {
                        Text(parent.replacingOccurrences(of: "::", with: " › "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)

                HStack(spacing: 0) {
                    stat("新規", counts.new, .blue)
                    Divider().frame(height: 44)
                    stat("学習中", counts.learning, .red)
                    Divider().frame(height: 44)
                    stat("復習", counts.review, .green)
                }
                .padding(.vertical, 16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    path.append(StudyRoute(ref: ref))
                } label: {
                    Label(counts.total > 0 ? "学習を開始" : "今日の学習は完了", systemImage: counts.total > 0 ? "play.fill" : "checkmark.circle")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(counts.total == 0)
                .keyboardShortcut(.defaultAction)

                Button {
                    path.append(BrowseRoute(ref: ref))
                } label: {
                    Label("カードを一覧表示", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if let col, let deck {
                    infoSection(col: col, deck: deck)
                }
                if let desc = deck?.description, !HTMLText.strip(desc).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("説明").font(.headline)
                        Text(HTMLText.strip(desc.replacingOccurrences(of: "<br>", with: "\n")))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(deck?.baseName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { model.refreshCounts() }
    }

    private func findNode() -> DeckNode? {
        func search(_ nodes: [DeckNode]) -> DeckNode? {
            for n in nodes {
                if n.deck.id == ref.deckID { return n }
                if let c = n.children, let found = search(c) { return found }
            }
            return nil
        }
        return search(model.deckTrees[ref.collectionID] ?? [])
    }

    private func stat(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func infoSection(col: AnkiCollection, deck: Deck) -> some View {
        let conf = col.deckConfig(for: deck.id)
        VStack(alignment: .leading, spacing: 10) {
            row("カード総数", "\(col.totalCards(in: deck.id))")
            row("オプション", conf.name)
            row("1日の新規カード上限", "\(deck.newLimit ?? conf.newPerDay)")
            row("1日の復習上限", "\(deck.reviewLimit ?? conf.reviewsPerDay)")
            row("スケジューラ", col.fsrsEnabled ? "FSRS（目標保持率 \(Int((conf.desiredRetention * 100).rounded()))%）" : "SM-2")
        }
        .font(.callout)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
