import XCTest

/// End-to-end demo tour: onboarding → demo scan → results, component flow and inspector → questions →
/// greener swaps and image → Compare → plug pairing → History → Settings.
/// Screenshots are attached at each stop so light and dark runs can be reviewed from the result bundle.
final class LiveGreenTourTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFullDemoTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-InMemoryStore", "YES", "-ScanMode", "photo",
                               "-PlugFeatures", "YES"]
        app.launch()

        completeOnboarding(app)
        runDeskScan(app)
        answerQuestionsIfOffered(app)
        inspectComponent(app)
        exploreAlternatives(app)
        checkCompare(app)
        openPlugPairing(app)
        checkHistory(app)
        checkSettings(app)
    }

    /// The other two demo scenes resolve, show results and load swaps.
    @MainActor
    func testLunchAndEBikeScenes() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-SkipOnboarding", "YES", "-InMemoryStore", "YES",
                               "-ScanMode", "photo"]
        app.launch()
        for (scene, file) in [("Lunch", "20-lunch"), ("E-bike corner", "21-ebike")] {
            let button = app.buttons[scene]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            let results = app.descendants(matching: .any)["confidenceMeter"]
            answerDetailsIfAsked(app, before: results, snapshot: file + "-details")
            XCTAssertTrue(results.waitForExistence(timeout: 30), "\(scene) opens results")
            let useEstimate = app.buttons["useEstimate"]
            if useEstimate.waitForExistence(timeout: 2) { useEstimate.tap() }
            snap(file)
            let open = app.buttons["openAlternatives"]
            for _ in 0..<5 where !open.isHittable { app.swipeUp() }
            open.tap()
            XCTAssertTrue(app.buttons["alternatives.generate"].waitForExistence(timeout: 30))
            snap(file + "-swaps")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    // MARK: - Steps

    @MainActor
    private func completeOnboarding(_ app: XCUIApplication) {
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Fresh install shows onboarding")
        snap("01-onboarding")
        for _ in 0..<12 where next.exists {
            if next.label.contains("Finish") {
                next.tap()
                break
            }
            next.tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func runDeskScan(_ app: XCUIApplication) {
        let desk = app.buttons["Desk setup"]
        XCTAssertTrue(desk.waitForExistence(timeout: 10))
        snap("02-scan")
        desk.tap()
        if app.descendants(matching: .any)["analyzingCard"].waitForExistence(timeout: 3) { snap("03-analyzing") }
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 30))
    }

    @MainActor
    private func answerQuestionsIfOffered(_ app: XCUIApplication) {
        let banner = app.descendants(matching: .any)["questionsBanner"]
        let apply = app.buttons["applyAnswers"]
        if !apply.waitForExistence(timeout: 2), banner.exists { banner.tap() }
        guard apply.waitForExistence(timeout: 3) else { return }
        snap("04-questions")
        // The desk monitor asks for hours per day; answer it and re-run the engine locally.
        let chip = app.buttons["~6 h"]
        if chip.exists { chip.tap() }
        if apply.isEnabled { apply.tap() } else { app.buttons["useEstimate"].tap() }
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func inspectComponent(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["confidenceMeter"].waitForExistence(timeout: 5))
        snap("05-results")

        let hotspot = app.descendants(matching: .any)["hotspot.27-inch monitor"]
        XCTAssertTrue(hotspot.waitForExistence(timeout: 5), "Desk scene has a monitor hotspot")
        hotspot.tap()
        XCTAssertTrue(app.descendants(matching: .any)["flowView"].waitForExistence(timeout: 5))
        snap("05b-component-flow")
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["metricInspector"].waitForExistence(timeout: 5))
        snap("05c-inspector")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertFalse(app.descendants(matching: .any)["flowView"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func exploreAlternatives(_ app: XCUIApplication) {
        let open = app.buttons["openAlternatives"]
        for _ in 0..<5 where !open.isHittable { app.swipeUp() }
        open.tap()
        let generate = app.buttons["alternatives.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 30))
        snap("07-alternatives")
        app.swipeUp()
        snap("08-comparison")
        XCTAssertTrue(generate.isEnabled)
        generate.tap()
        let slider = app.descendants(matching: .any)["Before and after comparison"]
        XCTAssertTrue(slider.waitForExistence(timeout: 30), "Demo image editor returns a greener image")
        snap("09-greener-image")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func checkCompare(_ app: XCUIApplication) {
        selectTab("Leaderboard", in: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "people like you"))
            .firstMatch.waitForExistence(timeout: 15))
        snap("10-compare")
        app.swipeUp()
        snap("10b-compare-leaderboard")
    }

    /// Pairing needs a real Shelly on the network, so the tour stops at the setup steps.
    @MainActor
    private func openPlugPairing(_ app: XCUIApplication) {
        selectTab("Plugs", in: app)
        let pair = app.buttons["plugs.pair"]
        XCTAssertTrue(pair.waitForExistence(timeout: 10))
        snap("11-plugs")
        pair.tap()
        XCTAssertTrue(app.buttons["pairing.find"].waitForExistence(timeout: 5))
        snap("12-pairing")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    private func checkHistory(_ app: XCUIApplication) {
        selectTab("History", in: app)
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The desk scan was saved")
        snap("16-history")
        row.tap()
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    private func checkSettings(_ app: XCUIApplication) {
        let settings = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.buttons["settings.editProfile"].waitForExistence(timeout: 5))
        snap("17-settings")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    /// Lunch's takeout box has no known material, so that scan asks one detail question before the results;
    /// answer it ("Foam") so the box moves to the factor model. Other scenes go straight to `results`.
    @MainActor
    private func answerDetailsIfAsked(_ app: XCUIApplication, before results: XCUIElement, snapshot: String) {
        let apply = app.buttons["specApply"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !apply.exists, !results.exists { Thread.sleep(forTimeInterval: 0.25) }
        guard apply.exists else { return }
        snap(snapshot)
        let foam = app.buttons["specOption.Foam"]
        if foam.exists { foam.tap() }
        if apply.isEnabled { apply.tap() } else { app.buttons["specSkip"].tap() }
    }

    /// The tab bar minimizes on scroll, so scroll back up until the tab is reachable.
    @MainActor
    private func selectTab(_ name: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[name]
        for _ in 0..<4 where !tab.exists { app.swipeDown() }
        tab.tap()
    }

    @MainActor
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
