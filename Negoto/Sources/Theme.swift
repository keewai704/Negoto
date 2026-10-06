import NegotoCore
import SwiftUI
import UIKit

/// Negoto's design tokens (design/Negoto.fig). Everything maps to system colours and Dynamic Type
/// text styles so the app follows Light/Dark mode, Increase Contrast and the system tint like Apple's apps.
/// Anki's conventions are kept: new = blue, learning = red, review = green.
enum Theme {
    // MARK: Colours

    static let accent = Color.accentColor
    static let background = Color(uiColor: .systemGroupedBackground)
    /// Opaque content blocks (lists, statistics, editors).
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator)

    static let new = Color(uiColor: .systemBlue)
    static let learning = Color(uiColor: .systemRed)
    static let review = Color(uiColor: .systemGreen)
    static let young = Color(uiColor: .systemTeal)
    static let mature = Color(uiColor: .systemGreen)
    static let suspended = Color(uiColor: .systemGray3)
    static let buried = Color(uiColor: .systemYellow)

    // Answer buttons.
    static func color(for rating: Rating) -> Color {
        switch rating {
        case .again: return Color(uiColor: .systemRed)
        case .hard: return Color(uiColor: .systemOrange)
        case .good: return Color(uiColor: .systemGreen)
        case .easy: return Color(uiColor: .systemBlue)
        }
    }

    static func title(for rating: Rating) -> String {
        switch rating {
        case .again: return "もう一度"
        case .hard: return "難しい"
        case .good: return "普通"
        case .easy: return "簡単"
        }
    }

    /// A stable colour for each deck's dot.
    static func deckColor(_ id: Int64) -> Color {
        let palette: [UIColor] = [.systemBlue, .systemOrange, .systemPurple, .systemTeal, .systemPink, .systemIndigo, .systemGreen]
        var h = UInt64(bitPattern: id) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        return Color(uiColor: palette[Int(h % UInt64(palette.count))])
    }

    // MARK: Metrics

    /// Corner radius of content blocks — concentric with the system's lists (larger on iOS 26).
    static var blockRadius: CGFloat {
        if #available(iOS 26.0, *) { return 26 }
        return 12
    }

    /// Readable widths.
    static let readableWidth: CGFloat = 720
    static let answerBarMaxWidth: CGFloat = 640
}

private struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    /// Reports the width this view is laid out at.
    func readWidth(into width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: ContainerWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(ContainerWidthKey.self) { value in
            if abs(width.wrappedValue - value) > 0.5 { width.wrappedValue = value }
        }
    }

    /// Centers content and limits its width on large windows.
    func readableWidth(_ width: CGFloat = 1100) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }

    /// An opaque content block, like a section of an inset-grouped list.
    func surface(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.blockRadius, style: .continuous))
    }
}

/// Keeps Forms and Lists at a readable width in wide windows while the scroll area stays full width.
struct ReadableScrollMargins: ViewModifier {
    var maxWidth: CGFloat = Theme.readableWidth

    func body(content: Content) -> some View {
        GeometryReader { geo in
            if geo.size.width > maxWidth + 40 {
                content.contentMargins(.horizontal, (geo.size.width - maxWidth) / 2, for: .scrollContent)
            } else {
                content
            }
        }
    }
}

extension View {
    func readableScrollMargins(_ maxWidth: CGFloat = Theme.readableWidth) -> some View { modifier(ReadableScrollMargins(maxWidth: maxWidth)) }
}

// MARK: - Components

/// Anki's three counts (new · learning · review) as right-aligned columns. Zero counts are dimmed, not hidden.
struct DeckCountsView: View {
    var counts: DeckCounts
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack(spacing: 4) {
            column(counts.new, Theme.new)
            column(counts.learning, Theme.learning)
            column(counts.review, Theme.review)
        }
        .font(font.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("新規\(counts.new)、学習中\(counts.learning)、復習\(counts.review)")
    }

    private func column(_ n: Int, _ color: Color) -> some View {
        Text("\(n)")
            .foregroundStyle(n > 0 ? color : Color(uiColor: .tertiaryLabel))
            .frame(minWidth: 30, alignment: .trailing)
    }
}

/// "新規 学習 復習" captions above count columns.
struct DeckCountsHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("新規").foregroundStyle(Theme.new).frame(minWidth: 30, alignment: .trailing)
            Text("学習").foregroundStyle(Theme.learning).frame(minWidth: 30, alignment: .trailing)
            Text("復習").foregroundStyle(Theme.review).frame(minWidth: 30, alignment: .trailing)
        }
        .font(.caption2.weight(.medium))
        .accessibilityHidden(true)
    }
}

/// "20 新規  3 学習中  48 復習" — the study toolbar. The kind of the current card is underlined, like Anki.
struct CountsInline: View {
    var counts: DeckCounts
    var highlight: QueuedCard.Kind?

    var body: some View {
        HStack(spacing: 12) {
            item(counts.new, "新規", Theme.new, highlight == .new)
            item(counts.learning, "学習中", Theme.learning, highlight == .learning)
            item(counts.review, "復習", Theme.review, highlight == .review)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("残り 新規\(counts.new)、学習中\(counts.learning)、復習\(counts.review)")
    }

    private func item(_ n: Int, _ label: String, _ color: Color, _ active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(n)").font(.headline.monospacedDigit()).foregroundStyle(color)
                .underline(active, color: color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// A large number with a caption (deck overview and statistics).
struct MetricView: View {
    var value: String
    var unit: String? = nil
    var caption: String
    var color: Color = .primary
    var font: Font = .title.weight(.bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(font.monospacedDigit()).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.footnote.weight(.medium)).foregroundStyle(.secondary) }
            }
            Text(caption).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Deck colour dot.
struct DeckDot: View {
    var id: Int64
    var body: some View {
        Circle().fill(Theme.deckColor(id)).frame(width: 9, height: 9)
    }
}

/// White glyph on a rounded colour square (Settings rows, like the Settings app).
struct SettingsIcon: View {
    var systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    /// The main call to action of a screen ("学習を始める", "答えを表示"): a large filled capsule.
    func primaryActionStyle() -> some View {
        self.buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
    }

    /// Secondary actions next to it ("カスタム学習", "オプション").
    func secondaryActionStyle() -> some View {
        self.buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
    }
}

/// Answer button: interval above the label, tinted with the rating's colour.
struct AnswerButtonStyle: ButtonStyle {
    var color: Color
    var height: CGFloat = 56
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(color.opacity(colorScheme == .dark ? 0.24 : 0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A capsule menu that shows a filter and its current value ("デッキ 英単語 ▾").
struct FilterChipLabel: View {
    var title: String
    var value: String?
    var active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(active ? Theme.accent : .secondary)
            if let value { Text(value).foregroundStyle(active ? Theme.accent : .primary).lineLimit(1) }
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(active ? Theme.accent : .secondary)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(active ? Theme.accent.opacity(0.14) : Theme.surface, in: Capsule())
        .overlay { if !active { Capsule().strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5) } }
        .contentShape(Capsule())
    }
}

/// Tags as wrapping chips.
struct FlowTags: View {
    var tags: [String]
    var onRemove: ((String) -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Group {
                    if let onRemove {
                        Button { onRemove(tag) } label: { chip(tag, removable: true) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("タグ「\(tag)」を外す")
                    } else {
                        chip(tag, removable: false)
                    }
                }
            }
        }
    }

    private func chip(_ tag: String, removable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(tag).lineLimit(1)
            if removable { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.accent.opacity(0.14), in: Capsule())
        .foregroundStyle(Theme.accent)
    }
}

enum Format {
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }

    static func percent(_ value: Double?, digits: Int = 0) -> String {
        guard let value else { return "–" }
        return String(format: "%.\(digits)f%%", value * 100)
    }

    static func number(_ n: Int) -> String { n.formatted(.number) }

    /// "今日 8:12", "昨日 21:03", "10/3".
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return "今日 \(time)" }
        if cal.isDateInYesterday(date) { return "昨日 \(time)" }
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }

    /// Days from now as "今日", "明日", "3日後", "2か月後".
    static func daysFromNow(_ days: Int) -> String {
        if days <= 0 { return "今日" }
        if days == 1 { return "明日" }
        if days < 60 { return "\(days)日後" }
        if days < 730 { return "\(days / 30)か月後" }
        return "\(days / 365)年後"
    }

    static func interval(days: Int) -> String {
        if days <= 0 { return "–" }
        if days < 60 { return "\(days)日" }
        if days < 730 { return String(format: "%.1fか月", Double(days) / 30) }
        return String(format: "%.1f年", Double(days) / 365)
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
