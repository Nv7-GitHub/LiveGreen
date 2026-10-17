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
        // Food carbon peers: median 2,000, σ 0.6. A user at 2,000·e^(−0.6) sits at z = −1 → greener than 1 − Φ(−1) = 84.13%.
        let footprint = ScannedFootprint(byCategory: [.food: [.carbon: 2_000 * exp(-0.6)]])
        let comparison = try #require(model().compare(footprint).first)
        #expect(comparison.metric == .carbon)
        #expect(abs(comparison.cohortMedian - 2_000) < 1e-9)
        #expect(abs(comparison.greenerThan - 0.841_344_746) < 1e-8)
        #expect(comparison.greenerThanPercent == 84)
        let atMedian = ScannedFootprint(byCategory: [.food: [.carbon: 2_000]])
        #expect(abs(try #require(model().compare(atMedian).first).greenerThan - 0.5) < 1e-12)
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
        let first = model().simulatedFriends(categories: [.food, .electronic])
        let second = model().simulatedFriends(categories: [.food, .electronic])
        #expect(first == second)
        #expect(first.count == 8)
        #expect(Set(first.map(\.name)).count == 8)
        #expect(first[0].initials == "MC")
        let values = first.compactMap { $0.yearly[.carbon] }
        #expect(values.count == 8 && Set(values).count == 8)
        #expect(first.allSatisfy { $0.yearly[.water] == nil })

        let footprint = ScannedFootprint(byCategory: [.food: [.carbon: 1_500]])
        let board = model().leaderboard(for: footprint)
        #expect(board.count == 9)
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
