import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Tier resolvers")
struct RecordResolverTests {
    private func request(_ component: Component, _ metrics: Set<MetricKey>? = nil) -> ResolutionRequest {
        ResolutionRequest(component: component, metrics: metrics ?? Set(component.category.applicableMetrics), profile: .default)
    }

    @Test func openFoodFactsScalesCarbonToOneServing() async throws {
        let can = Component(name: "Cola", category: .food, identifiers: Identifiers(gtin: "5449000000996"),
                            quantities: Quantities(massKg: 0.345, servingKg: 0.33))
        let output = try await OpenFoodFactsResolver(products: FakeProductDatabase()).resolve(request(can))
        let carbon = try #require(output.metrics[.carbon])
        #expect(abs(carbon.value - 0.47 * 0.33) < 1e-9)
        #expect(carbon.tier == .exactRecord)
        #expect(output.metrics[.recyclablePercent]?.value == 100)
        #expect(!output.stageShares.isEmpty)
    }

    @Test func openFoodFactsIgnoresElectronicsAndUnknownCodes() async throws {
        let resolver = OpenFoodFactsResolver(products: FakeProductDatabase())
        let laptop = Component(name: "Laptop", category: .electronic, identifiers: Identifiers(gtin: "5449000000996"))
        #expect(try await resolver.resolve(request(laptop)).metrics.isEmpty)
        let unknown = Component(name: "Snack", category: .food, identifiers: Identifiers(gtin: "0000000000000"))
        #expect(try await resolver.resolve(request(unknown)).metrics.isEmpty)
    }

    @Test func energyStarNeedsBrandAndModel() async throws {
        let resolver = EnergyStarResolver(appliances: FakeApplianceDatabase())
        let monitor = Component(name: "Monitor", category: .electronic, identifiers: Identifiers(brand: "Dell", model: "S2721H"))
        let output = try await resolver.resolve(request(monitor))
        #expect(output.metrics[.standbyPower]?.value == 0.3)
        #expect(output.metrics[.yearlyElectricity]?.tier == .exactRecord)
        let unbranded = Component(name: "Monitor", category: .electronic, identifiers: Identifiers(model: "S2721H"))
        #expect(try await resolver.resolve(request(unbranded)).metrics.isEmpty)
    }

    @Test func specResearchOnlyForBrandAndModel() async throws {
        let researcher = CountingResearcher()
        let resolver = SpecResearchResolver(researcher: researcher)
        let generic = Component(name: "Lamp", category: .electronic)
        #expect(try await resolver.resolve(request(generic)).metrics.isEmpty)
        #expect(await researcher.calls == 0)

        let monitor = Component(name: "Monitor", category: .electronic, identifiers: Identifiers(brand: "Dell", model: "S2721H"))
        let output = try await resolver.resolve(request(monitor, [.powerOn]))
        #expect(output.metrics[.powerOn]?.tier == .researchedSpec)
        #expect(await researcher.calls == 1)
    }

    @Test func specResearchRunsAtMostFourAtOnce() async throws {
        let researcher = CountingResearcher(delay: .milliseconds(30))
        let resolver = SpecResearchResolver(researcher: researcher, maxConcurrent: 4)
        let monitor = Component(name: "Monitor", category: .electronic, identifiers: Identifiers(brand: "Dell", model: "S2721H"))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { _ = try await resolver.resolve(request(monitor, [.powerOn])) }
            }
            try await group.waitForAll()
        }
        #expect(await researcher.calls == 10)
        #expect(await researcher.peak == 4)
    }

    @Test func estimatesStayWithinBoundedScales() async throws {
        let cup = Component(name: "Can", category: .packaging, fallbackEstimates: [
            .recyclablePercent: EstimateRange(value: 70, low: 50, high: 90),
            .carbon: EstimateRange(value: 0.1, low: 0.08, high: 0.12),
        ])
        let output = try await EstimateResolver().resolve(request(cup))
        let recyclable = try #require(output.metrics[.recyclablePercent])
        #expect(recyclable.high == 100)
        #expect(recyclable.low == 35)
        #expect(output.metrics[.carbon]?.low == 0.05)
    }
}

/// Records calls and the peak number running at once.
actor CountingResearcher: SpecResearcher {
    private(set) var calls = 0
    private(set) var peak = 0
    private var running = 0
    let delay: Duration

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func research(name: String, category: GreenCore.Category, identifiers: Identifiers,
                  metrics: [MetricKey]) async throws -> ResearchedSpec {
        calls += 1
        running += 1
        peak = max(peak, running)
        try await Task.sleep(for: delay)
        running -= 1
        let citation = Citation(url: URL(string: "https://example.com/spec")!, title: "Spec sheet",
                                quotedText: "Typical power 18 W")
        return ResearchedSpec(values: metrics.map { ResearchedValue(metric: $0, value: 18, citation: citation) })
    }
}
