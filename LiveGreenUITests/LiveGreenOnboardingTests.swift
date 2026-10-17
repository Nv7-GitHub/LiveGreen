import XCTest

/// Every onboarding control responds to a single tap, including taps on the empty part of a chip or capsule
/// away from its text (those used to miss), and Back keeps earlier answers.
final class LiveGreenOnboardingTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryOnboardingControlRespondsToOneTap() {
        let app = XCUIApplication()
        app.launchArguments = ["-DemoMode", "YES", "-InMemoryStore", "YES", "-ScanMode", "photo"]
        app.launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Fresh install shows onboarding")

        // Location: the whole country capsule opens the menu; the whole ZIP capsule focuses the field.
        let country = app.buttons["onboarding.country"]
        XCTAssertTrue(country.exists)
        country.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 3), "Country menu opens")
        // The menu is tall and centred; tap beside it to close it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForNonExistence(timeout: 3))

        let zip = app.textFields["onboarding.postalCode"]
        zip.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.15)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Capsule edge focuses the ZIP field")
        app.typeText("10001")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'NY'")).firstMatch.exists)
        let done = app.buttons["onboarding.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 2), "Number pad has a Done button")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        advance(app, to: "Who's in your household?")

        // Household stepper.
        let count = app.staticTexts["onboarding.household.count"]
        let start = Int(count.label) ?? 0
        app.buttons["onboarding.household.more"].tap()
        XCTAssertEqual(Int(count.label), start + 1)
        app.buttons["onboarding.household.fewer"].tap()
        XCTAssertEqual(Int(count.label), start)
        advance(app, to: "How do you eat?")

        for diet in ["Vegan", "Flexitarian", "Vegetarian", "Omnivore"] { tapChip(diet, in: app) }
        advance(app, to: "How do you get around?")

        tapChip("Work from home", in: app)
        tapChip("Car", in: app)
        XCTAssertFalse(app.buttons["Work from home"].isSelected, "Picking a commute mode clears Work from home")
        tapChip("Bike", in: app)
        advance(app, to: "What's home like?")

        tapChip("Detached house", in: app)
        tapChip("Heat pump", in: app)

        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.staticTexts["How do you get around?"].waitForExistence(timeout: 3), "Back goes back one")
        XCTAssertTrue(app.buttons["Bike"].isSelected && app.buttons["Car"].isSelected, "Back keeps answers")
        advance(app, to: "What's home like?")
        XCTAssertTrue(app.buttons["Heat pump"].isSelected)
        advance(app, to: "How do you shop for clothes?")

        tapChip("Mostly second-hand", in: app)
        advance(app, to: "What do you charge?")

        tapChip("Laptop", in: app)
        tapChip("Laptop", in: app, expectSelected: false)
        XCTAssertTrue(next.label.contains("Finish"))
        next.tap()
        XCTAssertTrue(app.tabBars.buttons["Scan"].waitForExistence(timeout: 10), "Finish closes onboarding")
    }

    /// One tap on Next shows the next question.
    @MainActor
    private func advance(_ app: XCUIApplication, to title: String) {
        app.buttons["onboarding.next"].tap()
        let heading = app.staticTexts[title]
        XCTAssertTrue(heading.exists || heading.waitForExistence(timeout: 3), "One tap on Next shows “\(title)”")
    }

    /// Taps a chip once, near its trailing edge (empty space, since labels are leading-aligned).
    @MainActor
    private func tapChip(_ name: String, in app: XCUIApplication, expectSelected: Bool = true) {
        let chip = app.buttons[name]
        XCTAssertTrue(chip.exists || chip.waitForExistence(timeout: 3), "\(name) chip exists")
        // Scroll until the whole chip is above Next (a half-visible chip counts as hittable).
        let limit = app.buttons["onboarding.next"].frame.minY - 12
        for _ in 0..<4 where chip.frame.maxY > limit { app.swipeUp(velocity: .slow) }
        XCTAssertGreaterThanOrEqual(chip.frame.height, 44, "\(name) chip is a 44 pt target")
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: expectSelected))
        let toggled = XCTNSPredicateExpectation(predicate: predicate, object: chip)
        XCTAssertEqual(XCTWaiter().wait(for: [toggled], timeout: 2), .completed,
                       "One tap \(expectSelected ? "selects" : "deselects") \(name)")
    }
}
