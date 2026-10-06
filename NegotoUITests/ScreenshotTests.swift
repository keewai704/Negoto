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

    private func openTab(_ app: XCUIApplication, _ names: String...) {
        // Tab bar (compact / medium) or sidebar rows (wide windows).
        for name in names {
            let candidates = [app.tabBars.buttons[name], app.cells[name].firstMatch, app.buttons[name].firstMatch,
                              app.staticTexts[name].firstMatch]
            if let element = candidates.first(where: { $0.exists && $0.isHittable }) {
                element.tap()
                sleep(1)
                return
            }
        }
        sleep(1)
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        if back.exists && back.isHittable { back.tap(); sleep(1) }
    }

    func testScreens() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-demo"]
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 60) { app.launch() }
        let study = app.buttons.matching(NSPredicate(format: "label CONTAINS '学習を始める'")).firstMatch
        XCTAssertTrue(study.waitForExistence(timeout: 60), "demo deck should be imported")
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            let prefix = "\(device)-\(orientation == .portrait ? "portrait" : "landscape")"

            openTab(app, "今日の学習", "デッキ")
            shot(app, "\(prefix)-1-decks")

            let deck = app.staticTexts["Math & Science"].firstMatch
            if deck.waitForExistence(timeout: 5) { deck.tap(); sleep(2) }
            shot(app, "\(prefix)-2-deck")
            goBack(app)

            openTab(app, "ブラウズ")
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5), (search.value as? String)?.contains("Hund") != true {
                search.tap()
                search.typeText("Hund\n")
                sleep(2)
            }
            let card = app.staticTexts["Hund"].firstMatch
            if card.waitForExistence(timeout: 5) { card.tap(); sleep(2) }
            shot(app, "\(prefix)-3-browse")
            goBack(app)

            openTab(app, "統計")
            sleep(2)
            shot(app, "\(prefix)-4-stats")

            openTab(app, "設定")
            shot(app, "\(prefix)-5-settings")

            openTab(app, "今日の学習", "デッキ")
            let add = app.buttons["追加メニュー"].firstMatch
            if add.waitForExistence(timeout: 5) {
                add.tap()
                sleep(2)
                shot(app, "\(prefix)-6-add-card")
                for name in ["閉じる", "キャンセル"] {
                    let close = app.buttons[name].firstMatch
                    if close.exists && close.isHittable { close.tap(); sleep(1); break }
                }
            }

            if study.waitForExistence(timeout: 5) {
                // The floating tab bar can cover the middle of the button: tap near its leading edge.
                study.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
                sleep(4)
                shot(app, "\(prefix)-7-study-question")
                let reveal = app.buttons["答えを表示"]
                if reveal.waitForExistence(timeout: 5) {
                    print("NEGOTO: reveal exists=\(reveal.exists) hittable=\(reveal.isHittable) frame=\(reveal.frame)")
                    reveal.tap()
                    let again = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'もう一度'")).firstMatch
                    if !again.waitForExistence(timeout: 5) {
                        print("NEGOTO: answer buttons missing after tapping reveal\n\(app.debugDescription)")
                    }
                    sleep(1)
                    shot(app, "\(prefix)-7-study-answer")
                    let info = app.buttons["カード情報"].firstMatch
                    if info.exists && info.isHittable {
                        info.tap()
                        sleep(2)
                        shot(app, "\(prefix)-8-study-inspector")
                        if !app.buttons["学習を終了"].isHittable { app.swipeDown(); sleep(1) }
                    }
                } else {
                    print("NEGOTO: no reveal button\n\(app.debugDescription)")
                }
                let close = app.buttons["学習を終了"]
                if close.exists { close.tap(); sleep(1) }
            }
        }
    }
}
