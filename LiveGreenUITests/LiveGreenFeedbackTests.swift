import XCTest

/// Scan feedback: a note left under a scan's results is confirmed, shown on the scan and listed in Settings.
final class LiveGreenFeedbackTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFeedbackIsSavedOnTheScanAndListedInSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-SkipOnboarding", "YES", "-InMemoryStore", "YES",
                               "-ScanMode", "photo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 10))
        app.buttons["Desk setup"].tap()

        // The desk scene can raise detail questions first, then gated usage questions on the results.
        let results = app.navigationBars["Desk setup"]
        let skip = app.buttons["specSkip"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !results.exists, !skip.exists { Thread.sleep(forTimeInterval: 0.25) }
        if skip.exists { skip.tap() }
        XCTAssertTrue(results.waitForExistence(timeout: 10))
        let useEstimate = app.buttons["useEstimate"]
        if useEstimate.waitForExistence(timeout: 3) { useEstimate.tap() }

        let open = app.descendants(matching: .any)["feedbackOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        for _ in 0..<6 where !open.isHittable { app.swipeUp() }
        open.tap()
        let field = app.descendants(matching: .any)["feedbackField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("The monitor is actually a TV")
        app.buttons["feedbackSubmit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["feedbackConfirmation"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The monitor is actually a TV"].waitForExistence(timeout: 3))

        // Reopened from History, the scan still shows its note.
        let history = app.tabBars.buttons["History"]
        for _ in 0..<4 where !history.exists { app.swipeDown() }
        history.tap()
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        let saved = app.staticTexts["The monitor is actually a TV"]
        for _ in 0..<6 where !saved.exists || !saved.isHittable { app.swipeUp() }
        XCTAssertTrue(saved.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let settings = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let clear = app.buttons["settings.clearFeedback"]
        for _ in 0..<8 where !clear.exists || !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.exists)
        XCTAssertTrue(app.staticTexts["The monitor is actually a TV"].exists)
    }
}
