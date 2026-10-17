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
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 20))
        skipQuestions(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["confidenceMeter"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testComponentAlternativesAndComparison() {
        let app = launch()
        app.buttons["Desk setup"].tap()
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 20))
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

        app.tabBars.buttons["Compare"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "people like you"))
            .firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor
    func testEBikeOffersSmartPlugAndMockPlugDashboard() {
        let app = launch(["-MockPlug", "YES"])
        app.buttons["E-bike corner"].tap()
        XCTAssertTrue(app.navigationBars["E-bike corner"].waitForExistence(timeout: 20))
        skipQuestions(in: app)

        let alternatives = app.descendants(matching: .any)["openAlternatives"]
        XCTAssertTrue(alternatives.waitForExistence(timeout: 5))
        alternatives.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "smart plug"))
            .firstMatch.waitForExistence(timeout: 20))

        app.tabBars.buttons["Plugs"].tap()
        // The mock plug is paired automatically, so the list offers pairing another one.
        XCTAssertTrue(app.buttons["Pair another plug"].waitForExistence(timeout: 10))
    }
}
