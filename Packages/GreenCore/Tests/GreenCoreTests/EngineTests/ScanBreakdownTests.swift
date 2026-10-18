import Foundation
import Testing
@testable import GreenCore

@Suite("Results breakdown on one per-year basis")
struct ScanBreakdownTests {
    /// A laptop kept 4 years: 286 kg CO2e over its life, 71.5 kg a year.
    private let laptop = Component(name: "Laptop", category: .electronic,
                                   metrics: [.carbon: .exact(286, unit: .kgCO2e, tier: .factorModel),
                                             .yearlyElectricity: .exact(37, unit: .kilowattHoursPerYear, tier: .exactRecord),
                                             .lifespan: .exact(4, unit: .years, tier: .factorModel)])
    /// A blended coffee twice a week: 1.48 kg CO2e a serving, ≈ 154 kg a year.
    private let drink = Component(name: "Blended coffee", category: .food,
                                  metrics: [.carbon: .exact(1.48, unit: .kgCO2e, tier: .factorModel),
                                            .water: .exact(250, unit: .liters, tier: .factorModel)],
                                  usage: UsageProfile(servingsPerWeek: 2))
    /// Its cup, used twice a week.
    private let cup = Component(name: "Plastic cup", category: .packaging,
                                metrics: [.carbon: .exact(0.03, unit: .kgCO2e, tier: .estimate),
                                          .water: .exact(0.5, unit: .liters, tier: .estimate)],
                                usage: UsageProfile(usesPerWeek: 2))

    @Test func rowsRankAndShareByYearNotByUnit() throws {
        let components = [laptop, drink]
        let breakdown = ScanBreakdown(components: components)
        // Per unit the laptop is 190× the drink; per year the drink is twice the laptop.
        #expect(try #require(breakdown.yearly(.carbon, of: laptop)).value == 71.5)
        #expect(abs(try #require(breakdown.yearly(.carbon, of: drink)).value - 153.92) < 1e-9)
        #expect(breakdown.ranked(components, by: .carbon).map(\.name) == ["Blended coffee", "Laptop"])
        let share = breakdown.share(of: drink, metric: .carbon, in: components)
        #expect(abs(share - 153.92 / (153.92 + 71.5)) < 1e-9)
        #expect(abs(share + breakdown.share(of: laptop, metric: .carbon, in: components) - 1) < 1e-9)
        // Electricity is already yearly.
        #expect(breakdown.yearly(.yearlyElectricity, of: laptop)?.value == 37)
    }

    @Test func numbersStayTheSameWhateverTheMetric() {
        let components = [cup, laptop, drink]
        let breakdown = ScanBreakdown(components: components)
        #expect(breakdown.numbers[drink.id] == 1)
        #expect(breakdown.numbers[laptop.id] == 2)
        #expect(breakdown.numbers[cup.id] == 3)
        // Water ranks only the drink and the cup, and the numbers do not change.
        let water = breakdown.ranked(components.filter { $0.metrics[.water] != nil }, by: .water)
        #expect(water.map { breakdown.number(of: $0) } == [1, 3])
    }

    @Test func dataQualityFollowsTheSelectedMetricWeightedByYear() throws {
        let components = [laptop, drink, cup]
        let breakdown = ScanBreakdown(components: components)
        let carbon = breakdown.tierShares(.carbon, in: components)
        #expect(carbon.map(\.tier) == [.factorModel, .estimate])
        // The cup's 0.03 kg × 104 = 3.12 kg a year is its weight, not its per-unit 0.03 kg.
        let cupShare = try #require(carbon.last).share
        #expect(abs(cupShare - 3.12 / (71.5 + 153.92 + 3.12)) < 1e-9)
        // Electricity has only the laptop's record.
        #expect(breakdown.tierShares(.yearlyElectricity, in: components).map(\.tier) == [.exactRecord])
        #expect(breakdown.confidence(.yearlyElectricity, in: components) == 1)
        #expect(breakdown.confidence(.carbon, in: components) == 0)
    }

    @Test func photoGuessesExcludeBarcodedItems() {
        var barcoded = drink
        barcoded.identifiers.gtin = "5449000000996"
        let components = [barcoded, cup]
        let breakdown = ScanBreakdown(components: components)
        let cupYear = 0.03 * 104, drinkYear = 1.48 * 104
        #expect(abs(breakdown.photoGuessedShare(.carbon, in: components) - cupYear / (cupYear + drinkYear)) < 1e-9)
        #expect(ScanBreakdown(components: [drink, cup]).photoGuessedShare(.carbon, in: [drink, cup]) == 1)
    }

    @Test func lifetimeCountsOnlyDurablesAndConsumablesOneEach() throws {
        let components = [laptop, drink, cup]
        let breakdown = ScanBreakdown(components: components)
        #expect(breakdown.isDurable(laptop))
        #expect(!breakdown.isDurable(drink))
        let lifetime = try #require(breakdown.lifetimeTotal(.carbon, in: components, seed: 1))
        #expect(lifetime == laptop.metrics[.carbon])
        let consumables = try #require(breakdown.consumablesTotal(.carbon, in: components, seed: 1))
        #expect(abs(consumables.value - 1.51) < 1e-9)
        // Nothing durable has water, so there is no lifetime water.
        #expect(breakdown.lifetimeTotal(.water, in: components, seed: 1) == nil)
    }

    @Test func assumptionsNameTheFrequencyOrLifespan() {
        let engine = ImpactEngine()
        #expect(engine.usageAssumption(for: drink) == .servingsPerWeek(2))
        #expect(engine.usageAssumption(for: cup) == .usesPerWeek(2))
        #expect(engine.usageAssumption(for: laptop) == .lifespan(years: 4))
        var pack = drink
        pack.quantities.packNetKg = 0.5
        pack.quantities.servingKg = 0.25
        pack.usage = UsageProfile(packsPerWeek: 0.5)
        #expect(engine.usageAssumption(for: pack) == .packsPerWeek(0.5))
        let plain = Component(name: "Apple", category: .food)
        #expect(engine.usageAssumption(for: plain) == .servingsPerWeek(FoodServing.defaultServingsPerWeek))
    }
}
