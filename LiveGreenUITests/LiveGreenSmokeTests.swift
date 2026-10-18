import XCTest

/// Spec §12 smoke tests: launch in Demo mode, run a fixture scan, open a component, the alternatives and
/// the comparison.
final class LiveGreenSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-SkipOnboarding", "YES", "-InMemoryStore", "YES",
                               "-ScanMode", "photo"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 10))
        return app
    }

    /// Waits for the results titled `title`, skipping the detail questions sheet a scan with T4 items shows first.
    @MainActor
    private func waitForResults(_ title: String, in app: XCUIApplication) -> Bool {
        let results = app.navigationBars[title]
        let skip = app.buttons["specSkip"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !results.exists, !skip.exists { Thread.sleep(forTimeInterval: 0.25) }
        if skip.exists { skip.tap() }
        return results.waitForExistence(timeout: 10)
    }

    /// Dismisses the gated questions sheet if the scan raised one.
    @MainActor
    private func skipQuestions(in app: XCUIApplication) {
        let useEstimate = app.buttons["useEstimate"]
        if useEstimate.waitForExistence(timeout: 3) { useEstimate.tap() }
    }

    @MainActor
    func testDemoScanShowsResults() {
        let app = launch()
        app.buttons["Desk setup"].tap()
        XCTAssertTrue(waitForResults("Desk setup", in: app))
        skipQuestions(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["confidenceMeter"].waitForExistence(timeout: 5))
    }

    /// The Lunch takeout box is a T4 estimate, so one detail question comes before the results.
    @MainActor
    func testLunchAsksForDetailsBeforeResults() {
        let app = launch()
        app.buttons["Lunch"].tap()
        let apply = app.buttons["specApply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 20), "The takeout box has no known material")
        XCTAssertFalse(apply.isEnabled, "Nothing picked yet")
        app.buttons["specOption.Foam"].tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(app.navigationBars["Lunch"].waitForExistence(timeout: 10))
        skipQuestions(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["confidenceMeter"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testComponentAlternativesAndComparison() {
        let app = launch()
        app.buttons["Desk setup"].tap()
        XCTAssertTrue(waitForResults("Desk setup", in: app))
        skipQuestions(in: app)

        let monitor = app.descendants(matching: .any)["componentRow.27-inch monitor"]
        XCTAssertTrue(monitor.waitForExistence(timeout: 5))
        monitor.tap()
        XCTAssertTrue(app.descendants(matching: .any)["flowView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["metricInspector"].exists)
        app.swipeDown(velocity: .fast)

        let alternatives = app.descendants(matching: .any)["openAlternatives"]
        XCTAssertTrue(alternatives.waitForExistence(timeout: 5))
        alternatives.tap()
        let generate = app.buttons["alternatives.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 20))
        XCTAssertTrue(generate.isEnabled, "Demo scans carry a photo, so the greener image can be generated")

        app.tabBars.buttons["Leaderboard"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "people like you"))
            .firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor
    func testEBikeOffersSmartPlugAndPairing() {
        let app = launch()
        app.buttons["E-bike corner"].tap()
        XCTAssertTrue(waitForResults("E-bike corner", in: app))
        skipQuestions(in: app)

        let alternatives = app.descendants(matching: .any)["openAlternatives"]
        XCTAssertTrue(alternatives.waitForExistence(timeout: 5))
        alternatives.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "smart plug"))
            .firstMatch.waitForExistence(timeout: 20))

        app.tabBars.buttons["Plugs"].tap()
        let pair = app.buttons["plugs.pair"]
        XCTAssertTrue(pair.waitForExistence(timeout: 10))
        pair.tap()
        XCTAssertTrue(app.buttons["pairing.find"].waitForExistence(timeout: 5), "Pairing starts with the setup steps")
    }

    @MainActor
    func testEraseAllDataFromSettings() {
        let app = launch()
        app.buttons["E-bike corner"].tap()
        XCTAssertTrue(waitForResults("E-bike corner", in: app))
        skipQuestions(in: app)
        app.tabBars.buttons["Scan"].tap()

        let settings = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let erase = app.buttons["settings.eraseAllData"]
        for _ in 0..<6 where !erase.isHittable { app.swipeUp() }
        erase.tap()
        let confirm = app.buttons["Erase everything"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10), "Onboarding starts again")
    }

    @MainActor
    func testRedoOnboardingFromSettings() {
        let app = launch()
        let settings = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let redo = app.buttons["settings.resetOnboarding"]
        XCTAssertTrue(redo.waitForExistence(timeout: 5))
        redo.tap()
        let confirm = app.buttons["Reset and start over"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10), "Onboarding shows again")
    }
}
