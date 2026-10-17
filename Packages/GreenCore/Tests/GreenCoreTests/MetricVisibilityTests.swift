import Testing
@testable import GreenCore

@Suite("Metric visibility")
struct MetricVisibilityTests {
    @Test func zeroValueAndRangeIsEffectivelyZero() {
        #expect(Measured.exact(0, unit: .grams, tier: .factorModel).isEffectivelyZero)
        #expect(Measured(value: 0.0001, low: 0, high: 0.0004, unit: .watts, tier: .estimate).isEffectivelyZero)
        // A zero estimate whose range reaches a real amount is still worth showing.
        #expect(!Measured(value: 0, low: 0, high: 5, unit: .grams, tier: .estimate).isEffectivelyZero)
        #expect(!Measured.exact(0.5, unit: .watts, tier: .exactRecord).isEffectivelyZero)
    }

    @Test func zeroPlasticAndStandbyAreHiddenButZeroRecyclableAndRepairabilityStay() {
        let spoon = Component(name: "Wooden spoon", category: .household, metrics: [
            .carbon: .exact(0.2, unit: .kgCO2e, tier: .factorModel),
            .plasticMass: .exact(0, unit: .grams, tier: .factorModel),
            .recyclablePercent: .exact(0, unit: .percent, tier: .factorModel),
        ])
        #expect(spoon.displayable(.plasticMass) == nil)
        #expect(spoon.displayable(.recyclablePercent) != nil)
        #expect(spoon.displayableMetrics == [.carbon, .recyclablePercent])

        let lamp = Component(name: "Lamp", category: .electronic, metrics: [
            .standbyPower: .exact(0, unit: .watts, tier: .researchedSpec),
            .repairability: .exact(0, unit: .score10, tier: .estimate),
        ])
        #expect(lamp.displayable(.standbyPower) == nil)
        #expect(lamp.displayable(.repairability) != nil)
    }

    @Test func missingAndInapplicableMetricsAreNotDisplayable() {
        let laptop = Component(name: "Laptop", category: .electronic, metrics: [
            .land: .exact(3, unit: .squareMeterYears, tier: .estimate),
        ])
        #expect(laptop.displayable(.land) == nil)
        #expect(laptop.displayable(.carbon) == nil)
        #expect(laptop.displayableMetrics.isEmpty)
    }
}
