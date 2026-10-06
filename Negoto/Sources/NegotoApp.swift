import SwiftUI

@main
struct NegotoApp: App {
    @State private var model = AppModel()
    @AppStorage(Settings.appearanceKey) private var appearance = Settings.Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(Settings.Appearance(rawValue: appearance)?.colorScheme)
                .onOpenURL { url in
                    model.importFiles([url])
                }
        }
    }
}

enum Settings {
    static let appearanceKey = "appearance"
    static let forceDarkCardsKey = "forceDarkCards"
    static let autoplayKey = "autoplayAudio"
    static let cardZoomKey = "cardZoom"
    static let showIntervalsKey = "showIntervals"
    static let showRemainingKey = "showRemaining"
    static let hapticsKey = "haptics"
    static let swipeKey = "swipeToAnswer"
    static let twoButtonsKey = "twoAnswerButtons"

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
        var title: String {
            switch self {
            case .system: return "システムに合わせる"
            case .light: return "ライト"
            case .dark: return "ダーク"
            }
        }
    }
}
