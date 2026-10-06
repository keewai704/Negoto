import XCTest

/// Walks through the main screens in portrait and landscape and attaches screenshots.
/// CI publishes them to the `screenshots` branch to review layouts on iPhone and iPad.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        // The whole-screen capture is correctly rotated in landscape (app.screenshot() is not).
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openTab(_ app: XCUIApplication, _ name: String) {
        // Tab bar (portrait) or sidebar cells (iPad landscape with the sidebar-adaptable tab view).
        let candidates = [app.tabBars.buttons[name], app.cells[name].firstMatch, app.buttons[name].firstMatch]
        if let element = candidates.first(where: { $0.exists && $0.isHittable }) {
            element.tap()
        }
        sleep(1)
    }

    func testScreens() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-demo"]
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 60) { app.launch() }
        let studyAll = app.buttons["すべてのデッキを学習"].firstMatch
        XCTAssertTrue(studyAll.waitForExistence(timeout: 60), "demo deck should be imported")
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            let prefix = "\(device)-\(orientation == .portrait ? "portrait" : "landscape")"

            openTab(app, "ホーム")
            shot(app, "\(prefix)-1-home")

            openTab(app, "デッキ")
            let deck = app.staticTexts["Math & Science"].firstMatch
            if deck.waitForExistence(timeout: 5) { deck.tap(); sleep(2) }
            shot(app, "\(prefix)-2-deck")
            if app.navigationBars.buttons.firstMatch.exists && UIDevice.current.userInterfaceIdiom != .pad {
                app.navigationBars.buttons.firstMatch.tap()
            }

            openTab(app, "統計")
            sleep(2)
            shot(app, "\(prefix)-3-stats")

            openTab(app, "設定")
            shot(app, "\(prefix)-5-settings")

            openTab(app, "ホーム")
            if studyAll.waitForExistence(timeout: 5) {
                studyAll.tap()
                sleep(3)
                shot(app, "\(prefix)-4-study-question")
                let reveal = app.buttons["解答を表示"]
                if reveal.waitForExistence(timeout: 5) {
                    reveal.tap()
                    sleep(2)
                    shot(app, "\(prefix)-4-study-answer")
                }
                let close = app.buttons["学習を終了"]
                if close.exists { close.tap(); sleep(1) }
            }
        }
    }
}
