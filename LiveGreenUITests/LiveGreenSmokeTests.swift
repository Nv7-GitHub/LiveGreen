import XCTest

final class LiveGreenSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoScanShowsResults() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-SkipOnboarding", "YES", "-InMemoryStore", "YES", "-ScanMode", "photo"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 10))
        app.buttons["Desk setup"].tap()
        XCTAssertTrue(app.navigationBars["Desk setup"].waitForExistence(timeout: 20))
    }
}
