import Foundation
import Testing
@testable import GreenCore

@Suite("Meal trends, action plans and Photon helpers")
struct ProactiveTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static func food(_ name: String, _ carbon: Double, category: GreenCore.Category = .food) -> Component {
        Component(name: name, category: category,
                  metrics: [.carbon: Measured(value: carbon, relativeRange: 0.2, unit: .kgCO2e, tier: .factorModel)])
    }

    private static func meal(_ day: Int, _ hour: Int, _ minute: Int = 0, items: [Component]) -> ScanResult {
        ScanResult(date: date(day, hour, minute), title: "Meal", components: items)
    }

    @Test func highCarbonLunchIsFlaggedWithItsBiggestItem() throws {
        let lunch = Self.meal(17, 12, 10, items: [Self.food("Beef burger", 3.2), Self.food("French fries", 0.4),
                                                  Self.food("Takeout box", 0.1, category: .packaging)])
        let trend = try #require(MealTrends.analyze([lunch], calendar: Self.calendar).first)
        #expect(trend.mealTime == .lunch)
        #expect(trend.topItemName == "Beef burger")
        #expect(abs(trend.latestCarbonKg - 3.7) < 0.001)
        #expect(trend.reason.contains("beef burger"))
    }

    @Test func aTitleNamingTheMealWinsOverTheClock() throws {
        var lunch = Self.meal(18, 3, 40, items: [Self.food("Beef burger", 3)])
        lunch.title = "Lunch"
        let trend = try #require(MealTrends.analyze([lunch], calendar: Self.calendar).first)
        #expect(trend.mealTime == .lunch)
        #expect(trend.typicalMinute == MealTime.lunch.usualStartMinute)
    }

    @Test func snacksGetNoMealNudge() {
        let lateNight = Self.meal(18, 3, 40, items: [Self.food("Beef jerky", 3)])
        #expect(MealTrends.analyze([lateNight], calendar: Self.calendar).isEmpty)
    }

    @Test func lowCarbonMealsAndNonFoodScansAreIgnored() {
        let salad = Self.meal(17, 12, items: [Self.food("Lentil salad", 0.6)])
        let desk = ScanResult(date: Self.date(17, 12), title: "Desk",
                              components: [Self.food("Monitor", 90, category: .electronic), Self.food("Laptop", 200, category: .electronic)])
        #expect(MealTrends.analyze([salad, desk], calendar: Self.calendar).isEmpty)
    }

    @Test func nudgeGoesOutBeforeTheTypicalMealTime() throws {
        let lunches = [Self.meal(15, 12, 30, items: [Self.food("Beef burger", 3)]),
                       Self.meal(16, 12, 0, items: [Self.food("Beef burger", 3)]),
                       Self.meal(17, 12, 10, items: [Self.food("Steak", 5)])]
        let trend = try #require(MealTrends.analyze(lunches, calendar: Self.calendar).first)
        #expect(trend.scanIDs.count == 3)
        #expect(trend.typicalMinute == 12 * 60 + 10)
        // At 9 am the nudge is today at 11:50; at 1 pm it moves to tomorrow.
        #expect(trend.nextSendDate(after: Self.date(18, 9), calendar: Self.calendar) == Self.date(18, 11, 50))
        #expect(trend.nextSendDate(after: Self.date(18, 13), calendar: Self.calendar) == Self.date(19, 11, 50))
    }

    @Test func placeQueriesFollowTheKindOfSwap() {
        let burger = Self.food("Beef burger", 3)
        let lentil = Alternative(name: "Lentil burger", category: .food, rationale: "")
        #expect(ActionPlanning.placeQueries(for: lentil, replacing: burger).first == "lentil burger")
        let laptop = Self.food("Laptop", 200, category: .electronic)
        let refurbished = Alternative(name: "Refurbished laptop", category: .electronic, rationale: "", condition: .refurbished)
        #expect(ActionPlanning.placeQueries(for: refurbished, replacing: laptop).first == "refurbished laptop")
        let tub = Alternative(name: "Protein powder in a bulk tub", category: .food, rationale: "")
        #expect(ActionPlanning.placeQueries(for: tub, replacing: Self.shake()) == ["protein powder", "grocery store", "supermarket"])
        let keep = Alternative(name: "Keep it two more years", category: .electronic, rationale: "")
        #expect(ActionPlanning.placeQueries(for: keep, replacing: laptop).isEmpty)
    }

    @Test func planParsingKeepsOnlyValidPlaceIndexes() throws {
        let input: JSONValue = ["headline": "Get a lentil burger at Clover", "place_index": 7,
                                "steps": [["title": "Walk over", "detail": .null], ["title": "  "]]]
        let draft = try PlanActionsTool.parse(input, placeCount: 3)
        #expect(draft.placeIndex == nil)
        #expect(draft.steps.map(\.title) == ["Walk over"])
    }

    @Test func localPlanNamesTheClosestPlace() {
        let place = NearbyPlace(name: "Clover Food Lab", address: "1075 Massachusetts Ave", latitude: 42.37,
                                longitude: -71.11, distanceMeters: 480)
        let request = ActionPlanRequest(original: Self.food("Beef burger", 3),
                                        alternative: Alternative(name: "Lentil burger", category: .food, rationale: "Lentils."),
                                        places: [place], profile: .default)
        let draft = LocalActionPlanner.draft(for: request)
        #expect(draft.placeIndex == 0)
        #expect(draft.headline.contains("Clover Food Lab"))
        #expect(draft.headline.contains("0.3 mi"))
    }

    @Test func phoneNumbersBecomeE164() {
        #expect(PhotonClient.e164("(617) 555-0123") == "+16175550123")
        #expect(PhotonClient.e164("1 617 555 0123") == "+16175550123")
        #expect(PhotonClient.e164("+44 20 7946 0958") == "+442079460958")
        #expect(PhotonClient.e164("555-0123") == nil)
    }

    // MARK: - Shopping

    private static func shake(plastic: Double = 28, swaps: [Alternative] = []) -> Component {
        var shake = Component(name: "Premier Protein shake", category: .food,
                              metrics: [.carbon: Measured(value: 0.6, relativeRange: 0.2, unit: .kgCO2e, tier: .factorModel),
                                        .plasticMass: Measured(value: plastic, relativeRange: 0.2, unit: .grams, tier: .factorModel)],
                              usage: UsageProfile(servingsPerWeek: 5))
        shake.alternatives = swaps
        return shake
    }

    private static func swap(_ name: String, carbon: Double, plastic: Double) -> Alternative {
        Alternative(name: name, category: .food, usage: UsageProfile(servingsPerWeek: 5), rationale: "",
                    metrics: [.carbon: Measured(value: carbon, relativeRange: 0.2, unit: .kgCO2e, tier: .factorModel),
                              .plasticMass: Measured(value: plastic, relativeRange: 0.2, unit: .grams, tier: .factorModel)])
    }

    @Test func shoppingIsSundayMorning() {
        // Oct 17 2026 is a Saturday.
        #expect(ShoppingTrends.nextShoppingDate(after: Self.date(17, 15), calendar: Self.calendar) == Self.date(18, 10))
        #expect(ShoppingTrends.nextShoppingDate(after: Self.date(18, 9), calendar: Self.calendar) == Self.date(18, 10))
        #expect(ShoppingTrends.nextShoppingDate(after: Self.date(18, 11), calendar: Self.calendar) == Self.date(25, 10))
    }

    @Test func bulkSwapNeedsABigPlasticCut() throws {
        let item = Self.shake(swaps: [Self.swap("Lighter bottle", carbon: 0.55, plastic: 25),
                                      Self.swap("Protein powder in a bulk tub", carbon: 0.4, plastic: 3)])
        let best = try #require(ShoppingTrends.bulkSwap(for: item))
        #expect(best.swap.name == "Protein powder in a bulk tub")
        #expect(best.cut > 0.85)
        #expect(ShoppingTrends.bulkSwap(for: Self.shake(swaps: [Self.swap("Lighter bottle", carbon: 0.55, plastic: 25)])) == nil)
    }

    @Test func shoppingTrendCountsRepeatScans() throws {
        let swaps = [Self.swap("Protein powder in a bulk tub", carbon: 0.4, plastic: 3)]
        let older = ScanResult(date: Self.date(15, 8), title: "Shake", components: [Self.shake(swaps: swaps)])
        let newer = ScanResult(date: Self.date(17, 8), title: "Shake", components: [Self.shake(swaps: swaps)])
        let noPlastic = ScanResult(date: Self.date(17, 9), title: "Apple",
                                   components: [Self.food("Apple", 0.1)])
        let trends = ShoppingTrends.analyze([older, newer, noPlastic])
        let trend = try #require(trends.first)
        #expect(trends.count == 1)
        #expect(trend.scanID == newer.id)
        #expect(trend.scanCount == 2)
        #expect(trend.reason.contains("2 times"))
        #expect(trend.reason.contains("buying in bulk"))
    }
}
