import XCTest

/// Every onboarding control responds to a single tap, including taps on the empty part of a chip or capsule
/// away from its text (those used to miss), sliders read out their answers, and Back keeps earlier answers.
/// A screenshot of each question is attached so the art can be reviewed from the result bundle.
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
        reveal(zip, in: app)
        zip.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.15)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "Capsule edge focuses the ZIP field")
        app.typeText("10001")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'NY'")).firstMatch.exists)
        let done = app.buttons["onboarding.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 2), "Number pad has a Done button")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        snap(app, "Where do you live?")
        advance(app, to: "Who's in your household?")

        // Household stepper.
        let count = app.staticTexts["onboarding.household.count"]
        let start = Int(count.label) ?? 0
        app.buttons["onboarding.household.more"].tap()
        XCTAssertEqual(Int(count.label), start + 1)
        app.buttons["onboarding.household.fewer"].tap()
        XCTAssertEqual(Int(count.label), start)
        advance(app, to: "How do you eat?")

        // Meat and dairy meals a week: the label reads out the count, and the live estimate follows.
        let estimate = app.descendants(matching: .any)["liveEstimate"]
        let before = estimate.label
        let meat = app.sliders["onboarding.meatMeals"]
        reveal(meat, in: app)
        XCTAssertEqual(meat.value as? String, "9 meals a week")
        meat.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(meat.value as? String, "None")
        waitForLabel(of: estimate, toChangeFrom: before, "Fewer meat meals lower the live estimate")
        let dairy = app.sliders["onboarding.dairyMeals"]
        reveal(dairy, in: app)
        dairy.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(dairy.value as? String, "Every meal")
        advance(app, to: "How do you get around?")

        // Only ways of getting around that emit carbon are offered, and none is a valid answer.
        for gone in ["Work from home", "Walk", "Bike"] {
            XCTAssertFalse(app.buttons[gone].exists, "\(gone) is no longer offered")
        }
        tapChip("Transit", in: app, expectSelected: false)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'None selected'")).firstMatch.exists)
        tapChip("Car", in: app)
        tapChip("E-bike", in: app)
        XCTAssertTrue(app.sliders["onboarding.distance.car"].exists, "A picked mode gets a distance slider")
        advance(app, to: "What's home like?")

        tapChip("Detached house", in: app)
        let area = app.sliders["onboarding.floorArea"]
        reveal(area, in: app)
        let typicalArea = area.value as? String
        area.adjust(toNormalizedSliderPosition: 0.6)
        let chosenArea = area.value as? String
        XCTAssertNotEqual(chosenArea, typicalArea, "The size slider moves off the typical size")
        // Heating is multi-select; No heating is exclusive.
        tapChip("Heat pump", in: app)
        XCTAssertTrue(app.buttons["Natural gas"].isSelected, "Picking a second heating source keeps the first")
        tapChip("No heating", in: app)
        XCTAssertFalse(app.buttons["Heat pump"].isSelected || app.buttons["Natural gas"].isSelected, "No heating clears sources")
        tapChip("Heat pump", in: app)
        XCTAssertFalse(app.buttons["No heating"].isSelected, "A heating source clears No heating")

        app.buttons["onboarding.back"].tap()
        XCTAssertTrue(app.staticTexts["How do you get around?"].waitForExistence(timeout: 3), "Back goes back one")
        XCTAssertTrue(app.buttons["Car"].isSelected && app.buttons["E-bike"].isSelected, "Back keeps answers")
        XCTAssertFalse(app.buttons["Transit"].isSelected)
        advance(app, to: "What's home like?")
        XCTAssertEqual(app.sliders["onboarding.floorArea"].value as? String, chosenArea)
        reveal(app.buttons["Heat pump"], in: app)
        XCTAssertTrue(app.buttons["Heat pump"].isSelected)
        advance(app, to: "How often do you buy new clothes?")

        let clothes = app.sliders["onboarding.newClothes"]
        reveal(clothes, in: app)
        XCTAssertEqual(clothes.value as? String, "64 a year")
        clothes.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(clothes.value as? String, "None")
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
        snap(app, title)
    }

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Scrolls the question until the whole element is above Next and below the top of the question's scroll
    /// area (a half-visible one counts as hittable, and one scrolled under the live estimate card takes no taps).
    /// Chips sit in a lazy grid, so ones below the fold only exist once scrolled to. Short drags that hold at
    /// the end, so a small phone's short scroll area isn't overshot by a swipe's momentum.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 1)
        let bottom = app.buttons["onboarding.next"].frame.minY - 12
        let top = app.scrollViews.firstMatch.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<8 {
            let up = !element.exists || element.frame.maxY > bottom
            guard up || element.frame.minY < top else { break }
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -150 : 150)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(element.exists, "\(element) exists")
    }

    /// Waits for an element's label to change after an answer.
    @MainActor
    private func waitForLabel(of element: XCUIElement, toChangeFrom label: String, _ message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", label), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 2), .completed, message)
    }

    /// Taps a chip once, near its trailing edge (empty space, since labels are leading-aligned).
    @MainActor
    private func tapChip(_ name: String, in app: XCUIApplication, expectSelected: Bool = true) {
        let chip = app.buttons[name]
        // `reveal` scrolls a chip below the fold into existence (the grid is lazy) and asserts it exists.
        reveal(chip, in: app)
        XCTAssertGreaterThanOrEqual(chip.frame.height, 44, "\(name) chip is a 44 pt target")
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: expectSelected))
        let toggled = XCTNSPredicateExpectation(predicate: predicate, object: chip)
        XCTAssertEqual(XCTWaiter().wait(for: [toggled], timeout: 2), .completed,
                       "One tap \(expectSelected ? "selects" : "deselects") \(name)")
    }
}
