import XCTest

/// Deleting scans from History: swiping a row, and Delete in an opened scan's menu. Each deletion leaves the
/// empty state, and the scan stays gone after leaving and reopening the tab.
final class LiveGreenHistoryTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches with a throwaway store, runs the Desk setup demo scan and opens History.
    @MainActor
    private func launchWithDeskScanInHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-SkipOnboarding", "YES", "-InMemoryStore", "YES",
                               "-ScanMode", "photo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 10))
        let desk = app.buttons["Desk setup"]
        XCTAssertTrue(desk.waitForExistence(timeout: 5))
        desk.tap()
        let results = app.navigationBars["Desk setup"]
        let skip = app.buttons["specSkip"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !results.exists, !skip.exists { Thread.sleep(forTimeInterval: 0.25) }
        if skip.exists { skip.tap() }
        XCTAssertTrue(results.waitForExistence(timeout: 10))
        skipQuestions(in: app)

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(row(in: app).waitForExistence(timeout: 5), "The scan is saved to History")
        return app
    }

    @MainActor
    private func row(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["historyRow.Desk setup"].firstMatch
    }

    /// Dismisses the gated questions sheet if the scan raised one.
    @MainActor
    private func skipQuestions(in app: XCUIApplication) {
        let useEstimate = app.buttons["useEstimate"]
        if useEstimate.waitForExistence(timeout: 3) { useEstimate.tap() }
    }

    /// The scan stays deleted: the empty state shows, and still shows after a round trip through another tab.
    @MainActor
    private func assertHistoryEmpty(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["No scans yet"].waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertFalse(row(in: app).exists, file: file, line: line)
        app.tabBars.buttons["Scan"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No scans yet"].waitForExistence(timeout: 5), file: file, line: line)
    }

    @MainActor
    func testSwipeToDeleteShowsEmptyState() {
        let app = launchWithDeskScanInHistory()
        row(in: app).swipeLeft()
        let delete = app.buttons["history.delete"].exists ? app.buttons["history.delete"] : app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        assertHistoryEmpty(app)
    }

    @MainActor
    func testDeleteFromOpenedScanAsksThenReturnsToHistory() {
        let app = launchWithDeskScanInHistory()
        row(in: app).tap()
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 5))
        skipQuestions(in: app)

        let menu = app.buttons["history.scanMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let deleteScan = app.buttons["history.deleteScan"]
        XCTAssertTrue(deleteScan.waitForExistence(timeout: 5))
        deleteScan.tap()
        // The dialog exposes its button twice (the button and its container).
        let confirm = app.buttons["history.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Deleting asks first")
        confirm.tap()

        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5), "Back on the list")
        assertHistoryEmpty(app)
    }
}
