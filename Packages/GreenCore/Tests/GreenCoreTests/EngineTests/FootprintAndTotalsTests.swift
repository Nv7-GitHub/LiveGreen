import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Footprint dedupe, cohort home modifiers and scan totals")
struct FootprintAndTotalsTests {
    private func monitor(_ id: UUID = UUID()) -> Component {
        Component(id: id, name: "Monitor", category: .electronic,
                  metrics: [.carbon: .exact(100, unit: .kgCO2e, tier: .factorModel),
                            .lifespan: .exact(5, unit: .years, tier: .factorModel)])
    }

    @Test func unitsInOneScanCountButRepeatScansReplace() {
        let engine = ImpactEngine()
        let desk = ScanResult(date: Date(timeIntervalSince1970: 1), title: "Desk", components: [monitor(), monitor()])
        let twoMonitors = ScannedFootprint.from(scans: [desk], engine: engine)
        #expect(twoMonitors.yearly[.carbon] == 40)

        let rescan = ScanResult(date: Date(timeIntervalSince1970: 2), title: "Desk again", components: [monitor()])
        #expect(ScannedFootprint.from(scans: [desk, rescan], engine: engine).yearly[.carbon] == 20)
        #expect(ScannedFootprint.from(scans: [rescan, desk], engine: engine).yearly[.carbon] == 20)
    }

    @Test func homeTypeAndHeatingShapeTheElectricityMedian() throws {
        let store = ReferenceStore.bundled
        let gas = try #require(CohortModel(profile: UserProfile(householdSize: 1, heating: .naturalGas), store: store))
        let electric = try #require(CohortModel(profile: UserProfile(householdSize: 1, heating: .electricResistance), store: store))
        let house = try #require(CohortModel(profile: UserProfile(householdSize: 1, homeType: .detachedHouse), store: store))
        let apartment = try #require(CohortModel(profile: UserProfile(householdSize: 1, homeType: .apartment), store: store))
        #expect(electric.median(for: .yearlyElectricity, categories: [.electronic])
                > gas.median(for: .yearlyElectricity, categories: [.electronic]))
        // Heating fuel does not change appliance carbon; home size does.
        #expect(electric.median(for: .carbon, categories: [.electronic]) == gas.median(for: .carbon, categories: [.electronic]))
        #expect(house.median(for: .carbon, categories: [.household]) > apartment.median(for: .carbon, categories: [.household]))
        #expect(house.median(for: .carbon, categories: [.food]) == apartment.median(for: .carbon, categories: [.food]))
    }

    @Test func rescanningTheSameBarcodeGivesIdenticalTotals() async throws {
        let store = ReferenceStore.bundled
        let ladder = EvidenceLadder(resolvers: [OpenFoodFactsResolver(products: FakeProductDatabase()),
                                                FactorModelResolver(store: store), EstimateResolver()],
                                    cache: InMemoryResolutionCache())
        let pipeline = ScanPipeline(vision: FakeVisionIdentifier(), alternatives: FakeAlternativeSuggester(),
                                    products: FakeProductDatabase(), ladder: ladder,
                                    engine: ImpactEngine(reference: store), profile: .default)
        let hints = OCRHints(gtins: ["5449000000996"])
        let first = try await pipeline.run(image: Data(), hints: hints, mode: .barcode)
        let second = try await pipeline.run(image: Data(), hints: hints, mode: .barcode)
        #expect(first.id != second.id)
        #expect(first.totals == second.totals)
        #expect(first.yearlyTotals == second.yearlyTotals)
        #expect(first.yearlyTotals[.carbon] != nil)
    }

    @Test func yearlyTotalsAnnualizeAndOldScansDecode() throws {
        var scan = ScanResult(title: "Desk", components: [monitor()])
        scan.updateTotals(engine: ImpactEngine())
        #expect(scan.totals[.carbon]?.value == 100)
        #expect(scan.yearlyTotals[.carbon]?.value == 20)

        // A scan saved before yearly totals existed still decodes.
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(scan)) as? [String: Any])
        json.removeValue(forKey: "yearlyTotals")
        let legacy = try JSONDecoder().decode(ScanResult.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.yearlyTotals.isEmpty)
        #expect(legacy.totals == scan.totals)
    }
}
