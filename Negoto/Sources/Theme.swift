import NegotoCore
import SwiftUI

/// Negoto's visual language: a calm "night study" theme taken from the app icon
/// (indigo → violet night sky, warm moon), quiet surfaces, and clear colour coding.
enum Theme {
    static let nightTop = Color(red: 0.11, green: 0.12, blue: 0.33)
    static let nightBottom = Color(red: 0.36, green: 0.21, blue: 0.58)
    static let moon = Color(red: 1.0, green: 0.78, blue: 0.30)

    static var night: LinearGradient {
        LinearGradient(colors: [nightTop, nightBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Card states (Anki's convention: blue new, red learning, green review)
    static let new = Color(red: 0.27, green: 0.55, blue: 0.96)
    static let learning = Color(red: 0.94, green: 0.42, blue: 0.36)
    static let review = Color(red: 0.20, green: 0.70, blue: 0.47)
    static let young = Color(red: 0.49, green: 0.80, blue: 0.56)
    static let mature = Color(red: 0.13, green: 0.55, blue: 0.36)
    static let suspended = Color(red: 0.96, green: 0.76, blue: 0.27)
    static let buried = Color.gray

    // Answer buttons
    static func color(for rating: Rating) -> Color {
        switch rating {
        case .again: return Color(red: 0.91, green: 0.30, blue: 0.33)
        case .hard: return Color(red: 0.95, green: 0.58, blue: 0.20)
        case .good: return Color(red: 0.19, green: 0.68, blue: 0.45)
        case .easy: return Color(red: 0.26, green: 0.55, blue: 0.96)
        }
    }

    static func title(for rating: Rating) -> String {
        switch rating {
        case .again: return "もう一度"
        case .hard: return "難しい"
        case .good: return "正解"
        case .easy: return "簡単"
        }
    }

    static let cornerRadius: CGFloat = 20
    static let maxContentWidth: CGFloat = 1280
}

/// Width classes used for responsive layouts (measured from the actual container, so Split View,
/// Slide Over and Stage Manager windows of any size are handled, not just device types).
enum LayoutWidth: Comparable {
    /// iPhone portrait, narrow windows (< 600pt)
    case compact
    /// iPhone landscape, iPad portrait, medium windows (600–999pt)
    case medium
    /// iPad landscape, large windows (≥ 1000pt)
    case wide

    init(_ width: CGFloat) {
        switch width {
        case ..<600: self = .compact
        case ..<1000: self = .medium
        default: self = .wide
        }
    }

    /// Number of columns for grids of small tiles.
    var tileColumns: Int {
        switch self {
        case .compact: return 2
        case .medium: return 4
        case .wide: return 4
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 16
        case .medium: return 24
        case .wide: return 32
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
}

/// Lays out two columns side by side when there's room, otherwise stacks them.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    /// Width available to the columns (measured with `readWidth`).
    var width: CGFloat
    var sideBySide: Bool
    var leadingFraction: CGFloat = 0.5
    var spacing: CGFloat = 20
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if sideBySide && width > 0 {
            HStack(alignment: .top, spacing: spacing) {
                VStack(spacing: spacing) { leading }
                    .frame(width: max(0, (width - spacing) * leadingFraction))
                VStack(spacing: spacing) { trailing }
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: spacing) {
                leading
                trailing
            }
        }
    }
}

/// A rounded surface used for every content block.
struct Surface<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold))
            if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small coloured counts: new / learning / review. Zero counts are hidden; a check mark when done.
struct DuePills: View {
    var counts: DeckCounts
    var size: Size = .regular

    enum Size { case small, regular }

    var body: some View {
        HStack(spacing: 4) {
            if counts.total == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary.opacity(0.5))
                    .font(size == .small ? .footnote : .callout)
            } else {
                pill(counts.new, Theme.new)
                pill(counts.learning, Theme.learning)
                pill(counts.review, Theme.review)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("新規\(counts.new)、学習中\(counts.learning)、復習\(counts.review)")
    }

    @ViewBuilder
    private func pill(_ n: Int, _ color: Color) -> some View {
        if n > 0 {
            Text("\(n)")
                .font((size == .small ? Font.caption : Font.footnote).weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .padding(.horizontal, size == .small ? 6 : 8)
                .padding(.vertical, size == .small ? 2 : 3)
                .background(color.opacity(0.14), in: Capsule())
        }
    }
}

/// A labelled number, used on Home and Statistics.
struct StatTile: View {
    var icon: String
    var title: String
    var value: String
    var tint: Color = .accentColor

    var body: some View {
        Surface(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var onNight = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(onNight ? Theme.nightTop : .white)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(onNight ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.accentColor))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Answer button: tinted surface with the interval above the label.
struct RatingButtonStyle: ButtonStyle {
    var color: Color
    var fillHeight = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: fillHeight ? 44 : 58, maxHeight: fillHeight ? .infinity : nil)
            .foregroundStyle(color)
            .background(color.opacity(configuration.isPressed ? 0.26 : 0.14),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Keeps Forms and Lists at a readable width in wide windows while the scroll area stays full width.
struct ReadableScrollMargins: ViewModifier {
    var maxWidth: CGFloat = 760

    func body(content: Content) -> some View {
        GeometryReader { geo in
            if geo.size.width > maxWidth + 40 {
                content.contentMargins(.horizontal, (geo.size.width - maxWidth) / 2, for: .scrollContent)
            } else {
                // Keep the system's own margins (inset grouped style) on narrow screens.
                content
            }
        }
    }
}

struct AdaptiveTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

extension View {
    func readableScrollMargins(_ maxWidth: CGFloat = 760) -> some View { modifier(ReadableScrollMargins(maxWidth: maxWidth)) }

    /// Centers content and limits its width on large windows (iPad / Stage Manager).
    func readableWidth(_ width: CGFloat = Theme.maxContentWidth) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

enum Format {
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Liquid Glass
//
// Following Apple's guidance, Liquid Glass is used for the navigation/control layer only
// (tab bar, toolbars, floating study controls, buttons); content (cards, charts) stays on
// opaque surfaces. On iOS 17/18 the same shapes fall back to system materials.

extension View {
    /// A glass background in the given shape (material on older systems).
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.18)) }
                }
            }
        }
    }

    /// Identifies a glass element so it morphs between states inside a `GlassGroup`.
    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// The main call to action: prominent glass (or a filled button before iOS 26).
    @ViewBuilder
    func primaryActionStyle(onNight: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if onNight {
                self.buttonStyle(.glassProminent).tint(.white).controlSize(.large).foregroundStyle(Theme.nightTop)
            } else {
                self.buttonStyle(.glassProminent).controlSize(.large)
            }
        } else {
            self.buttonStyle(PrimaryButtonStyle(onNight: onNight))
        }
    }

    /// Secondary actions: regular glass buttons.
    @ViewBuilder
    func secondaryActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).controlSize(.large)
        } else {
            self.buttonStyle(SecondaryButtonStyle())
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

/// Groups glass elements so they blend and morph together (plain stack before iOS 26).
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

/// iOS 26 tab bar behaviours: minimise on scroll, and a glass accessory above the tab bar.
struct GlassTabBarModifier<Accessory: View>: ViewModifier {
    @ViewBuilder var accessory: Accessory
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            // Landscape phones have little vertical room: drop the accessory there.
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: verticalSizeClass != .compact) { accessory }
        } else if #available(iOS 26.0, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory { accessory }
        } else {
            content
        }
    }
}

extension View {
    /// Makes a button label span the available width (for full-width glass buttons).
    func wideLabel(minHeight: CGFloat = 34) -> some View {
        font(.headline).frame(maxWidth: .infinity, minHeight: minHeight)
    }
}
