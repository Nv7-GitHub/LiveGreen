import XCTest

/// The Leaderboard's metric chips switch with a single tap, including taps on the empty part of a chip away from
/// its text (those used to miss) and quick taps in a row; every metric with a baseline has a chip.
final class LiveGreenLeaderboardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMetricChipsSwitchOnOneTap() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-SkipOnboarding", "YES", "-InMemoryStore", "YES",
                               "-ScanMode", "photo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 10))
        app.buttons["Desk setup"].tap()
        let results = app.navigationBars["Desk setup"]
        let skip = app.buttons["specSkip"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !results.exists, !skip.exists { Thread.sleep(forTimeInterval: 0.25) }
        if skip.exists { skip.tap() }
        XCTAssertTrue(results.waitForExistence(timeout: 10))
        let useEstimate = app.buttons["useEstimate"]
        if useEstimate.waitForExistence(timeout: 3) { useEstimate.tap() }

        app.tabBars.buttons["Leaderboard"].tap()
        let metrics = [("carbon", "Whole yearly footprint"), ("yearlyElectricity", "Yearly home electricity"),
                       ("water", "Yearly water use"), ("land", "Yearly land use")]
        let chips = metrics.map { app.buttons["leaderboard.metric.\($0.0)"] }
        XCTAssertTrue(chips[0].waitForExistence(timeout: 15))
        XCTAssertTrue(chips.allSatisfy(\.exists), "Carbon, electricity, water and land each have a chip")
        XCTAssertTrue(chips[0].isSelected)

        // Each tap lands on the chip's empty left edge, away from its icon and text, and switches at once.
        for index in [2, 3, 1, 0, 3, 2, 0, 1] {
            chips[index].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
            XCTAssertTrue(chips[index].isSelected, "\(metrics[index].0) is selected after one tap")
            XCTAssertTrue(app.staticTexts[metrics[index].1].exists, "The board shows \(metrics[index].1)")
        }

        XCTAssertFalse(app.staticTexts["Percentile over time"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "simulated"))
            .firstMatch.exists)
    }
}
