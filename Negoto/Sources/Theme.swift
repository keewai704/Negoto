import NegotoCore
import SwiftUI
import UIKit

/// Negoto's design system (from the "Adaptive iOS/iPadOS Flashcards" design):
/// a calm teal accent, opaque content (cards and lists) and Liquid Glass only for the navigation layer.
///
/// Tokens: spacing 4–24, radius cell 10 · input 12 · card 24. Light and dark variants are dynamic colours.
enum Theme {
    // MARK: Colours

    static let accent = dynamic(light: 0x3B7D6C, dark: 0x5FD1B3)
    /// Text on top of the accent colour.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x062A21)
    static let accentSoft = dynamic(light: 0xDCEDE7, dark: 0x1B3A32)

    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surfaceRaised = dynamic(light: 0xF2F2F7, dark: 0x2C2C2E)
    static let separator = Color(uiColor: .separator)
    static let input = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)

    // Card states: blue new, red learning, green review (Anki's convention).
    static let new = dynamic(light: 0x2F6FE4, dark: 0x5B9BFF)
    static let learning = dynamic(light: 0xD9443F, dark: 0xFF6B63)
    static let review = dynamic(light: 0x2E9A55, dark: 0x4CD37A)
    static let young = dynamic(light: 0x8FD1B3, dark: 0x3E8F72)
    static let mature = accent
    static let suspended = dynamic(light: 0xC7C7CC, dark: 0x636366)
    static let buried = dynamic(light: 0xE5B53C, dark: 0xC99A2E)

    // Answer buttons.
    static func color(for rating: Rating) -> Color {
        switch rating {
        case .again: return dynamic(light: 0xD9443F, dark: 0xFF6B63)
        case .hard: return dynamic(light: 0xD27C14, dark: 0xF5A43A)
        case .good: return dynamic(light: 0x2E9A55, dark: 0x4CD37A)
        case .easy: return dynamic(light: 0x2F6FE4, dark: 0x5B9BFF)
        }
    }

    static func background(for rating: Rating) -> Color {
        switch rating {
        case .again: return dynamic(light: 0xFBE3E2, dark: 0x3A1715)
        case .hard: return dynamic(light: 0xFBEBD6, dark: 0x3A2A10)
        case .good: return dynamic(light: 0xDDF1E3, dark: 0x13311E)
        case .easy: return dynamic(light: 0xDEE8FB, dark: 0x13213D)
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
        let palette: [Color] = [review, buried, new, learning, accent,
                                dynamic(light: 0x8E5BD6, dark: 0xB48CFF), dynamic(light: 0x1F9DB8, dark: 0x4CC8E0)]
        var h = UInt64(bitPattern: id) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        return palette[Int(h % UInt64(palette.count))]
    }

    // MARK: Metrics

    enum Radius {
        static let cell: CGFloat = 10
        static let input: CGFloat = 12
        static let block: CGFloat = 18
        static let card: CGFloat = 24
    }

    /// Readable width of the study card.
    static let cardMaxWidth: CGFloat = 680
    /// Answer bar width.
    static let answerBarMaxWidth: CGFloat = 560

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let v = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Layout is chosen from the window's actual width, not the device type
/// (Compact < 600pt · Medium 600–1023pt · Wide ≥ 1024pt, with ±16pt hysteresis at the edges).
enum LayoutClass: Comparable {
    case compact, medium, wide

    static func resolve(width: CGFloat, previous: LayoutClass?) -> LayoutClass {
        let hysteresis: CGFloat = 16
        func plain(_ w: CGFloat) -> LayoutClass { w < 600 ? .compact : (w < 1024 ? .medium : .wide) }
        guard let previous else { return plain(width) }
        let target = plain(width)
        if target == previous { return previous }
        // Only switch once the width is clearly past the boundary.
        switch (previous, target) {
        case (.compact, _): return width >= 600 + hysteresis ? target : previous
        case (.medium, .compact): return width < 600 - hysteresis ? target : previous
        case (.medium, .wide): return width >= 1024 + hysteresis ? target : previous
        case (.wide, _): return width < 1024 - hysteresis ? target : previous
        default: return target
        }
    }
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

    /// An opaque content block (lists, statistics, editors).
    func surface(padding: CGFloat = 16, radius: CGFloat = Theme.Radius.block) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    /// Inner panes (list / detail) keep their own navigation bar even though the wide layout hides
    /// the split view's outer bar.
    func paneNavigationBar() -> some View { toolbar(.visible, for: .navigationBar) }
}

/// Keeps Forms and Lists at a readable width in wide windows while the scroll area stays full width.
struct ReadableScrollMargins: ViewModifier {
    var maxWidth: CGFloat = 760

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
    func readableScrollMargins(_ maxWidth: CGFloat = 760) -> some View { modifier(ReadableScrollMargins(maxWidth: maxWidth)) }
}

// MARK: - Components

/// A small section heading ("すべてのデッキ", "学習"…).
struct SectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Count badges: new · learning · review. Zero counts are dimmed, not hidden, so columns line up.
struct CountBadges: View {
    var counts: DeckCounts
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            CountBadge(value: counts.new, color: Theme.new)
            CountBadge(value: counts.learning, color: Theme.learning)
            CountBadge(value: counts.review, color: Theme.review)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("新規\(counts.new)、学習中\(counts.learning)、復習\(counts.review)")
    }
}

struct CountBadge: View {
    var value: Int
    var color: Color

    var body: some View {
        Text("\(value)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(value > 0 ? color : Color.secondary.opacity(0.5))
            .frame(minWidth: 18)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(value > 0 ? color.opacity(0.13) : Color.secondary.opacity(0.08), in: Capsule())
    }
}

/// "12 新規  3 学習  48 復習" — used in the study header.
struct CountsInline: View {
    var counts: DeckCounts
    var highlight: QueuedCard.Kind?

    var body: some View {
        HStack(spacing: 10) {
            item(counts.new, "新規", Theme.new, highlight == .new)
            item(counts.learning, "学習", Theme.learning, highlight == .learning)
            item(counts.review, "復習", Theme.review, highlight == .review)
        }
    }

    private func item(_ n: Int, _ label: String, _ color: Color, _ active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(n)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
                .underline(active, color: color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// A large number with a caption (deck detail and statistics).
struct MetricView: View {
    var value: String
    var unit: String? = nil
    var caption: String
    var color: Color = .primary
    var size: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: size, weight: .bold).monospacedDigit()).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Deck colour dot.
struct DeckDot: View {
    var id: Int64
    var body: some View {
        Circle().fill(Theme.deckColor(id)).frame(width: 8, height: 8)
    }
}

/// Filled call-to-action in the accent colour ("学習を始める", "答えを表示").
struct AccentButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Tinted secondary action ("カスタム学習", "オプション").
struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(Theme.accent)
            .background(Theme.accentSoft.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
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

// MARK: - Liquid Glass (navigation layer only)

extension View {
    /// A glass background in the given shape (material before iOS 26).
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint.opacity(0.18)) }
                }
            }
        }
    }

    /// Round glass icon button (close, more…).
    @ViewBuilder
    func circularGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large)
        }
    }
}

/// Groups glass elements so they blend together (plain content before iOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// A glass capsule holding a row of icon buttons (study toolbar).
struct GlassToolbarCluster<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .glassBackground(in: Capsule(), interactive: true)
    }
}

struct ToolbarIcon: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
