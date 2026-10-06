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
    static let maxContentWidth: CGFloat = 880
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(color)
            .background(color.opacity(configuration.isPressed ? 0.26 : 0.14),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
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
