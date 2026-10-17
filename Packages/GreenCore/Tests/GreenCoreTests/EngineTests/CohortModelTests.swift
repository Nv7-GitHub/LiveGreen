import Foundation
import Testing
@testable import GreenCore

@Suite("Cohort model and percentiles")
struct CohortModelTests {
    /// Hand-built baseline so expected values can be computed by hand.
    let baseline = PerCapitaBaseline(
        region: "TEST", medians: [.carbon: 10_000, .water: 1_000_000, .land: 6_000, .yearlyElectricity: 5_000],
        sigmas: [.carbon: 0.6, .water: 0.5, .land: 0.6, .yearlyElectricity: 0.5],
        dietModifiers: [.omnivore: 1, .flexitarian: 0.83, .vegetarian: 0.68, .vegan: 0.51],
        householdSizeExponent: 0.75, citation: Source(title: "Test", tier: .factorModel))
    let reference = CohortReference(
        categoryShares: [.carbon: [.food: 0.2, .electronic: 0.1], .yearlyElectricity: [.electronic: 0.3]],
        clothingModifiers: [:], commuteModifiers: [.car: 1.1], citations: [])

    func model(_ profile: UserProfile = UserProfile(householdSize: 1)) -> CohortModel {
        CohortModel(profile: profile, baseline: baseline, reference: reference)
    }

    @Test func medianAppliesSharesAndModifiers() {
        #expect(model().median(for: .carbon, categories: [.food]) == 2_000)
        let vegan = model(UserProfile(householdSize: 1, diet: .vegan))
        #expect(abs(vegan.median(for: .carbon, categories: [.food]) - 1_020) < 1e-9)
        // Household of 4: electronic share × 4^(0.75 − 1).
        let family = model(UserProfile(householdSize: 4))
        #expect(abs(family.median(for: .carbon, categories: [.electronic]) - 1_000 * pow(4, -0.25)) < 1e-9)
        #expect(abs(model().median(for: .carbon, categories: [.food, .electronic]) - 3_000) < 1e-9)
        #expect(model().distribution(for: .water, categories: [.food]) == nil) // no share
        #expect(abs(model(UserProfile(commuteMode: .car)).wholeFootprintMedian(for: .carbon) - 11_000) < 1e-9)
    }

    @Test func percentileMatchesHandComputedCDF() throws {
        // Median 2,000, σ 0.6. A value of 2,000·e^(−0.6) sits at z = −1 → greener than 1 − Φ(−1) = 84.13%.
        let peers = LogNormal(median: 2_000, sigma: 0.6)
        #expect(abs(Percentiles.greenerThan(2_000 * exp(-0.6), in: peers) - 0.841_344_746) < 1e-8)
        #expect(abs(Percentiles.greenerThan(2_000, in: peers) - 0.5) < 1e-12)
    }

    @Test func estimateIsTheWholeFootprintWithScansWhereTheyExceedIt() throws {
        // Food 2,000 + electronic 1,000 + transit 50 km/wk × 0.10 × 52 = 260 + the rest 10,000 × (1 − 0.3 − 0.2).
        #expect(abs(try #require(model().estimate(for: .carbon)) - 8_260) < 1e-9)
        // A scan below the category's typical amount leaves it alone; one above it replaces it.
        let light = ScannedFootprint(byCategory: [.food: [.carbon: 500]])
        #expect(abs(try #require(model().estimate(for: .carbon, scanned: light)) - 8_260) < 1e-9)
        let heavy = ScannedFootprint(byCategory: [.food: [.carbon: 3_740]])
        #expect(abs(try #require(model().estimate(for: .carbon, scanned: heavy)) - 10_000) < 1e-9)
        // Peers are the whole region, unadjusted: carbon median 10,000; home electricity 30% of 5,000.
        #expect(abs(try #require(model(UserProfile(householdSize: 1, diet: .vegan)).regionalDistribution(for: .carbon)).median - 10_000) < 1e-9)
        #expect(abs(try #require(model().regionalDistribution(for: .yearlyElectricity)).median - 1_500) < 1e-9)
        #expect(model().regionalDistribution(for: .water) == nil)

        let comparison = try #require(model().compare(heavy).first { $0.metric == .carbon })
        #expect(abs(comparison.userValue - 10_000) < 1e-9)
        #expect(abs(comparison.cohortMedian - 10_000) < 1e-9)
        #expect(abs(comparison.greenerThan - 0.5) < 1e-12)
        let typical = try #require(model().compare(light).first { $0.metric == .carbon })
        #expect(abs(typical.greenerThan - (1 - Normal.cdf(log(0.826) / 0.6))) < 1e-12)
    }

    @Test func footprintFromScansDeduplicatesAndAnnualizes() throws {
        var older = SampleScansForTests.desk
        older.date = Date(timeIntervalSince1970: 1_780_000_000)
        var newer = ScanResult(title: "Desk again", components: [older.components[0]])
        newer.components[0].metrics[.carbon] = .exact(400, unit: .kgCO2e, tier: .exactRecord)
        newer.date = Date(timeIntervalSince1970: 1_790_000_000)
        let footprint = ScannedFootprint.from(scans: [newer, older])
        // Laptop counted once from the newer scan: 400 ÷ 4 years.
        #expect(try #require(footprint.byCategory[.electronic]?[.carbon]) == 100)
        #expect(abs(try #require(footprint.byCategory[.food]?[.carbon]) - 11.9 * 104) < 1e-9)
        #expect(footprint.categories(for: .carbon) == [.electronic, .food, .packaging])
    }

    @Test func friendsAreDeterministicAndLabeled() throws {
        let first = model().simulatedFriends()
        let second = model().simulatedFriends()
        #expect(first == second)
        #expect(first.count == CohortModel.friendNames.count)
        #expect(Set(first.map(\.name)) == Set(CohortModel.friendNames))
        #expect(first.map(\.name) != CohortModel.friendNames, "names are dealt in shuffled order")
        #expect(first.first { $0.name == "Yuti Purohit" }?.initials == "YP")
        let values = first.compactMap { $0.yearly[.carbon] }
        #expect(values.count == CohortModel.friendNames.count && Set(values).count == values.count)
        #expect(first.allSatisfy { $0.yearly[.water] == nil })

        let footprint = ScannedFootprint(byCategory: [.food: [.carbon: 1_500]])
        let board = model().leaderboard(for: footprint)
        #expect(board.count == CohortModel.friendNames.count + 1)
        #expect(board.filter(\.isUser).count == 1)
        #expect(zip(board, board.dropFirst()).allSatisfy { $0.value <= $1.value })
    }

    @Test func trendRecomputesAfterEachScan() {
        var first = SampleScansForTests.desk
        first.date = Date(timeIntervalSince1970: 1_780_000_000)
        var second = ScanResult(title: "Lunch", components: [first.components[1]])
        second.components[0].name = "Second burger"
        second.date = Date(timeIntervalSince1970: 1_790_000_000)
        let store = ReferenceStore.bundled
        let real = CohortModel(profile: .default, store: store)!
        let trend = Percentiles.trend(scans: [second, first], model: real)
        #expect(trend.count == 2)
        #expect(trend[0].date < trend[1].date)
        #expect(trend.allSatisfy { (0...1).contains($0.greenerThan) })
    }
}

@Suite("Leaderboard against bundled baselines")
struct LeaderboardRealismTests {
    static let typical = UserProfile(householdSize: 2, commuteKmPerWeekByMode: [.car: 150], homeType: .detachedHouse)
    static let green = UserProfile(householdSize: 3, diet: .vegan, commuteKmPerWeekByMode: [.bike: 40],
                                   homeType: .apartment, clothingHabit: .mostlySecondHand)
    static let heavy = UserProfile(householdSize: 1, commuteKmPerWeekByMode: [.car: 500], homeType: .detachedHouse,
                                   heating: .electricResistance, clothingHabit: .mostlyNew)
    /// A laptop, a burger twice a week and a cup: far less than any whole category.
    let scanned = ScannedFootprint.from(scans: [SampleScansForTests.desk])

    func model(_ profile: UserProfile) throws -> CohortModel { try #require(CohortModel(profile: profile, store: .bundled)) }

    func rank(_ profile: UserProfile, _ metric: MetricKey = .carbon) throws -> Int {
        let board = try model(profile).leaderboard(for: scanned, metric: metric)
        #expect(board.count == CohortModel.friendNames.count + 1)
        return try #require(board.firstIndex { $0.isUser }) + 1
    }

    @Test func friendsHaveRealisticWholeFootprints() throws {
        let us = try model(UserProfile(region: Region(countryCode: "US")))
        let usMedian = try #require(us.regionalDistribution(for: .carbon)).median
        #expect((14_000...16_500).contains(usMedian), "US per-capita carbon median \(usMedian)")
        let carbon = us.simulatedFriends().compactMap { $0.yearly[.carbon] }.sorted()
        #expect(carbon.count == 9 && carbon.allSatisfy { (6_000...36_000).contains($0) }, "\(carbon)")
        #expect((11_000...20_000).contains(carbon[4]), "middle friend \(carbon[4])")
        let electricity = us.simulatedFriends().compactMap { $0.yearly[.yearlyElectricity] }
        #expect(electricity.count == 9 && electricity.allSatisfy { (1_200...10_000).contains($0) }, "\(electricity)")

        // Every region and state: friends sit within ~2σ of their own regional median.
        let regions = ["US", "GB", "IN", "DE", "CN", "BR", "AU"].map { Region(countryCode: $0) }
            + ["MA", "TX", "WY", "CA"].map { Region(countryCode: "US", usState: $0) }
        for region in regions {
            let model = try model(UserProfile(region: region))
            for metric in CohortModel.leaderboardMetrics {
                let distribution = try #require(model.regionalDistribution(for: metric))
                for friend in model.simulatedFriends() {
                    let z = log(try #require(friend.yearly[metric]) / distribution.median) / distribution.sigma
                    #expect(abs(z) < 2, "\(region.countryCode) \(region.usState ?? "") \(metric) \(friend.name) z=\(z)")
                }
            }
        }
        // Production-based state figures no longer halve or sextuple a state's footprint.
        let ratio = try model(UserProfile(region: Region(countryCode: "US", usState: "WY"))).regionalDistribution(for: .carbon)!.median / usMedian
        #expect(abs(ratio - 1.25) < 1e-9)
    }

    @Test func rankFollowsTheProfile() throws {
        #expect(try rank(.default) > 1, "the default profile does not win")
        #expect((4...7).contains(try rank(Self.typical)), "typical profile lands mid-pack")
        #expect(try rank(Self.green) <= 3, "very green profile is near the top")
        #expect(try rank(Self.heavy) >= 8, "car-heavy profile is near the bottom")
        #expect(try rank(Self.heavy, .yearlyElectricity) >= 8)
        #expect(try rank(Self.green, .yearlyElectricity) <= 3)
        let percent = { (profile: UserProfile) in try #require(self.model(profile).compare(self.scanned).first).greenerThan }
        #expect(try percent(Self.green) > percent(Self.typical) && percent(Self.typical) > percent(Self.heavy))
    }

    @Test func estimateMatchesOnboardingAndAddsBigScans() throws {
        for profile in [UserProfile.default, Self.typical, Self.green, Self.heavy] {
            let estimate = try #require(try model(profile).estimate(for: .carbon))
            #expect(abs(estimate - LifestyleEstimate(profile: profile).totalKg) < 1e-6)
        }
        // A daily steak habit is more than a typical diet, so it raises the footprint.
        let typical = try model(Self.typical)
        let base = try #require(typical.estimate(for: .carbon, scanned: scanned))
        let steak = ScannedFootprint(byCategory: [.food: [.carbon: 4_000]])
        #expect(try #require(typical.estimate(for: .carbon, scanned: steak)) > base)
        #expect(try #require(typical.compare(scanned).first).metric == .carbon)
        #expect(typical.compare(scanned).map(\.metric) == CohortModel.leaderboardMetrics)
    }
}

@Suite("LifestyleEstimate")
struct LifestyleEstimateTests {
    @Test func travelComesFromDistancePerMode() {
        let profile = UserProfile(commuteKmPerWeekByMode: [.car: 100, .transit: 50, .bike: 30])
        let estimate = LifestyleEstimate(profile: profile)
        // (100 × 0.25 + 50 × 0.10 + 30 × 0) × 52 weeks.
        #expect(abs((estimate.kgPerYear[.travel] ?? 0) - 1_560) < 1e-6)
    }

    @Test func greenerAnswersLowerTheEstimate() {
        let base = LifestyleEstimate(profile: UserProfile(diet: .omnivore, commuteKmPerWeekByMode: [.car: 200]))
        let greener = LifestyleEstimate(profile: UserProfile(diet: .vegan, commuteKmPerWeekByMode: [.bike: 200],
                                                             clothingHabit: .mostlySecondHand))
        #expect(greener.totalKg < base.totalKg)
        #expect((greener.kgPerYear[.food] ?? 0) < (base.kgPerYear[.food] ?? 0))
        #expect(greener.kgPerYear[.travel] == 0)
        #expect(base.regionAverageKg > 0)
    }

    @Test func legacyProfilesDecodeIntoOneMode() throws {
        let json = #"""
            {"region":{"countryCode":"US"},"householdSize":1,"diet":"vegan","commuteMode":"car","commuteKmPerWeek":80,
             "homeType":"apartment","heating":"heatPump","clothingHabit":"mixed","chargingItems":[],"onboardingCompleted":true}
            """#
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        #expect(profile.commuteKmPerWeekByMode == [.car: 80])
        #expect(profile.commuteMode == .car)
        let roundTrip = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        #expect(roundTrip == profile)
    }
}

@Suite("Editable usage")
struct EditableUsageTests {
    let engine = ImpactEngine()

    @Test func electronicsDefaultToTheDeviceTypicalHours() {
        let monitor = Component(name: "Monitor", category: .electronic, quantities: Quantities(deviceType: "monitor"))
        let fields = engine.editableUsage(for: monitor)
        #expect(fields.map(\.field) == [.hoursOnPerDay, .standbyHoursPerDay])
        #expect(fields[0].value + fields[1].value == 24)
    }

    @Test func phoneHoursAlsoSetCharges() {
        let phone = Component(name: "Phone", category: .electronic, quantities: Quantities(deviceType: "smartphone"))
        guard engine.batteryKWh(for: phone) != nil else { return }
        let edits = engine.usageEdits(.hoursOnPerDay, 9, for: phone)
        #expect(edits.map(\.field) == [.hoursOnPerDay, .chargesPerWeek])
        #expect(edits[1].value == 9 * 7 / ImpactEngine.activeHoursPerCharge)
    }
}

@Suite("Brewed coffee")
struct BrewedCoffeeTests {
    @Test func aCupCountsOnlyItsGrounds() async throws {
        let cup = Component(name: "Coffee cup", category: .food,
                            quantities: Quantities(massKg: 0.35, servingKg: 0.35, foodGroup: "coffee"))
        let beans = Component(name: "Bag of coffee beans", category: .food,
                              quantities: Quantities(massKg: 0.34, servingKg: 0.015, foodGroup: "coffee"))
        let resolver = FactorModelResolver(store: .bundled)
        let cupCarbon = try await resolver.resolve(ResolutionRequest(component: cup, metrics: [.carbon], profile: UserProfile())).metrics[.carbon]
        let beansCarbon = try await resolver.resolve(ResolutionRequest(component: beans, metrics: [.carbon], profile: UserProfile())).metrics[.carbon]
        // 0.35 kg × 6% grounds × 28.5 kg CO2e/kg ≈ 0.6 kg, not ≈ 10 kg for the whole drink.
        #expect(try #require(cupCarbon).value < 1)
        #expect(abs(try #require(beansCarbon).value - 0.015 * 28.53) < 0.01)
    }
}
