import Foundation
import Testing
@testable import GreenCore

@Suite("Model")
struct ModelTests {
    @Test func measuredNormalizesRange() {
        let m = Measured(value: 10, low: 12, high: 8, unit: .kgCO2e, tier: .estimate)
        #expect(m.low == 8)
        #expect(m.high == 12)
        #expect(m.spreadRatio == 1.5)
    }

    @Test func measuredRelativeRangeAndScaling() {
        let m = Measured(value: 100, relativeRange: 0.5, unit: .watts, tier: .factorModel).scaled(by: 2)
        #expect(m.value == 200)
        #expect(m.low == 100)
        #expect(m.high == 300)
    }

    @Test func everyCategoryHasCarbonAndUnitsMatch() {
        for category in GreenCore.Category.allCases {
            #expect(category.applicableMetrics.first == .carbon)
            #expect(Set(category.applicableMetrics).count == category.applicableMetrics.count)
        }
        #expect(MetricKey.allCases.count == 12)
        #expect(MetricKey.yearlyElectricity.unit == .kilowattHoursPerYear)
        #expect(GreenCore.Category.food.applies(.waterPollution))
        #expect(!GreenCore.Category.food.applies(.powerOn))
        #expect(GreenCore.Category.electronic.applies(.repairability))
    }

    @Test func identifierCacheKeyPrefersGTIN() {
        #expect(Identifiers(gtin: "123", brand: "A", model: "B").cacheKey == "gtin:123")
        #expect(Identifiers(brand: "Dell", model: "S2721H").cacheKey == "bm:dell|s2721h")
        #expect(Identifiers(brand: "Dell").cacheKey == nil)
    }

    @Test func scanResultRoundTripsThroughJSONWithKeyedMetrics() throws {
        var component = Component(name: "Lamp", category: .electronic)
        component.metrics[.powerOn] = .exact(8, unit: .watts, tier: .exactRecord,
                                             sources: [Source(title: "Spec", url: URL(string: "https://example.com"), tier: .exactRecord)])
        component.stageShares = [.use: 0.7, .materials: 0.3]
        let result = ScanResult(title: "Desk", components: [component], totals: ScanTotals.sum([component]))
        let data = try JSONEncoder().encode(result)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"powerOn\""))
        #expect(try JSONDecoder().decode(ScanResult.self, from: data) == result)
    }

    @Test func scanSeedIsStablePerID() {
        let id = UUID()
        #expect(ScanResult(id: id, title: "a").seed == ScanResult(id: id, title: "b").seed)
    }

    @Test func usageFieldSubscriptSetsValue() {
        let usage = UsageProfile(hoursOnPerDay: 2).setting(.hoursOnPerDay, to: 6)
        #expect(usage.hoursOnPerDay == 6)
        #expect(usage[.servingsPerWeek] == nil)
    }

    @Test func plugScheduleWindowsAreContiguous() {
        let schedule = PlugSchedule(onHours: [14, 1, 2, 3, 13, 25])
        #expect(schedule.onHours == [1, 2, 3, 13, 14])
        #expect(schedule.windows == [1..<4, 13..<15])
    }

    @Test func plugCandidateRequiredHours() {
        #expect(PlugCandidate(loadType: .eBike, chargerWatts: 200, dailyKWh: 0.5).requiredHoursPerDay == 2.5)
    }

    @Test func researchedSpecDropsUncitedValues() {
        let cited = Citation(url: URL(string: "https://example.com/spec")!, title: "Spec", quotedText: "18 W typical")
        let uncited = Citation(url: URL(string: "https://example.com/x")!, title: "X", quotedText: " ")
        let spec = ResearchedSpec(values: [
            ResearchedValue(metric: .standbyPower, value: 0.5, citation: uncited),
            ResearchedValue(metric: .powerOn, value: 18, citation: cited),
        ])
        #expect(spec.measured.keys.sorted { $0.rawValue < $1.rawValue } == [.powerOn])
        #expect(spec.measured[.powerOn]?.tier == .researchedSpec)
    }
}
