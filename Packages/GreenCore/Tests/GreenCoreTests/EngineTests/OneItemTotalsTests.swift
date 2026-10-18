import Foundation
import Testing
@testable import GreenCore

/// A scene total over one item is that item's own figure, so the summary and the item's inspector agree to the
/// last digit (the flyer in testing_images 25 showed 0.012–0.035 gal against 0.012–0.036).
@Suite("One-item totals")
struct OneItemTotalsTests {
    private static let source = Source(title: "Paper factor", url: nil, tier: .factorModel)

    /// Stored, not computed: an item without a resolution key seeds its Monte Carlo from its id.
    private let flyer = Component(
        name: "Yellow paper flyer", category: .packaging,
        metrics: [.carbon: Measured(value: 0.0033, low: 0.0021, high: 0.0045, unit: .kgCO2e, tier: .factorModel, sources: [Self.source]),
                  .water: Measured(value: 0.09, low: 0.045, high: 0.135, unit: .liters, tier: .factorModel, sources: [Self.source])],
        usage: UsageProfile(usesPerWeek: 1))

    private let bike = Component(name: "Bicycle", category: .household,
                                 metrics: [.carbon: Measured(value: 86, low: 52, high: 121, unit: .kgCO2e, tier: .factorModel),
                                           .water: Measured(value: 400, low: 200, high: 600, unit: .liters, tier: .factorModel)])

    @Test func aSingleItemsTotalsAreItsOwnFigures() {
        let engine = ImpactEngine()
        for item in [flyer, bike] {
            var scan = ScanResult(title: "One item", components: [item])
            scan.updateTotals(engine: engine)
            #expect(scan.totals[.water] == item.metrics[.water])
            #expect(scan.totals[.carbon] == item.metrics[.carbon])
            // The scan's seed differs from the item's, but the yearly total is still the item's own per-year figure.
            #expect(scan.yearlyTotals[.carbon] == engine.carbonViews(of: item)?.perYear)
            #expect(scan.yearlyTotals[.water] == engine.yearly(.water, of: item))
        }
    }

    @Test func aConsumablesYearIsItsRangeTimesTheCountExactly() throws {
        let yearly = try #require(ImpactEngine().yearly(.water, of: flyer))
        let weeks = ImpactEngine.weeksPerYear
        #expect(yearly == Measured(value: 0.09 * weeks, low: 0.045 * weeks, high: 0.135 * weeks, unit: .liters,
                                   tier: .factorModel, sources: [Self.source]))
    }

    @Test func theOnlyItemWithAMetricOwnsThatTotal() {
        let engine = ImpactEngine()
        var dryFlyer = flyer
        dryFlyer.metrics[.water] = nil
        let totals = engine.itemTotals([dryFlyer, bike], seed: 7)
        let yearly = engine.yearlyTotals([dryFlyer, bike], seed: 7)
        #expect(totals[.water] == bike.metrics[.water])
        #expect(yearly[.water] == engine.yearly(.water, of: bike))
        // Two items still add up through one joint Monte Carlo.
        let carbon = totals[.carbon]
        #expect(carbon?.value == 0.0033 + 86)
        #expect(carbon != bike.metrics[.carbon])
    }

    @Test func simpleSumsKeepAnItemsSources() {
        #expect(ScanTotals.sum([flyer])[.carbon] == flyer.metrics[.carbon])
        #expect(ScanTotals.sum([flyer, flyer])[.carbon]?.sources == [])
    }
}
