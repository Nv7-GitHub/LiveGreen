import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Items recognized to their brand and model line (a Mac told from its keyboard) rather than a printed model number:
/// the line reaches spec research and line-level records, and a low-confidence guess does not.
@Suite("Model lines")
struct ModelLineTests {
    private struct FixedVision: VisionIdentifier {
        var components: [IdentifiedComponent]
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
            IdentifyResponse(components: components, sceneTitle: nil)
        }
    }

    /// Records what it was asked and answers with fixed cited values.
    private struct RecordingResearcher: SpecResearcher {
        let asked = Recorder<Identifiers>()
        var values: [ResearchedValue] = []
        func research(name: String, category: GreenCore.Category, identifiers: Identifiers,
                      metrics: [MetricKey]) async throws -> ResearchedSpec {
            asked.append(identifiers)
            return ResearchedSpec(values: values.filter { metrics.contains($0.metric) })
        }
    }

    static let reportCarbon = ResearchedValue(metric: .carbon, value: 150, citation: Citation(
        url: URL(string: "https://example.com/laptop-environmental-report.pdf")!,
        title: "Laptop environmental report", quotedText: "Carbon footprint excluding use: 150 kg CO2e"))

    private func laptop(_ name: String, _ identifiers: Identifiers) -> Component {
        Component(name: name, category: .electronic, identifiers: identifiers,
                  quantities: Quantities(screenSizeInches: 14, deviceType: "laptop"))
    }

    @Test func researchRunsForABrandAndConfidentModelLine() async throws {
        let researcher = RecordingResearcher(values: [Self.reportCarbon])
        let resolver = SpecResearchResolver(researcher: researcher)
        func resolve(_ identifiers: Identifiers) async throws -> ResolverOutput {
            try await resolver.resolve(ResolutionRequest(component: laptop("MacBook Pro 14-inch", identifiers),
                                                         metrics: [.carbon], profile: .default))
        }
        let medium = try await resolve(Identifiers(brand: "Apple", modelLine: "MacBook Pro 14-inch (M-series)", confidence: .medium))
        #expect(medium.metrics[.carbon]?.tier == .researchedSpec)
        #expect(researcher.asked.values.first?.modelLine == "MacBook Pro 14-inch (M-series)")
        #expect(researcher.asked.values.first?.model == nil)

        // A low-confidence guess, a line without a brand, or a brand alone is not researched.
        _ = try await resolve(Identifiers(brand: "Apple", modelLine: "MacBook Air", confidence: .low))
        _ = try await resolve(Identifiers(modelLine: "MacBook Air", confidence: .high))
        _ = try await resolve(Identifiers(brand: "Apple", confidence: .high))
        #expect(researcher.asked.values.count == 1)
    }

    @Test func researchPromptDescribesTheLine() {
        let ids = Identifiers(brand: "Apple", modelLine: "MacBook Pro 14-inch (M-series)", confidence: .medium,
                              appearanceCues: "⌘ keys, notch, HDMI port")
        let text = ClaudeClient.researchUserText(name: "Apple MacBook Pro 14-inch", category: .electronic,
                                                 identifiers: ids, metrics: [.carbon, .powerOn])
        #expect(text.contains("Brand: Apple"))
        #expect(text.contains("Model line: MacBook Pro 14-inch (M-series)"))
        #expect(text.contains("No model number is known (recognized from its appearance, medium confidence; cues: ⌘ keys, notch, HDMI port)."))
        #expect(!text.contains("Model: "))
        #expect(ClaudeClient.researchSystemPrompt.contains("When only a model line is given"))

        let printed = ClaudeClient.researchUserText(name: "Monitor", category: .electronic,
                                                    identifiers: Identifiers(brand: "Dell", model: "S2721H", modelLine: "S series"),
                                                    metrics: [.powerOn])
        #expect(printed.contains("Model: S2721H") && !printed.contains("No model number"))
    }

    @Test func asusLaptopsMatchTheirLineReports() async throws {
        let store = ReferenceStore.bundled
        func resolve(_ identifiers: Identifiers) async throws -> ResolverOutput {
            try await ASUSPCFResolver(store: store).resolve(ResolutionRequest(
                component: laptop("ASUS Zenbook 14 OLED", identifiers), metrics: Set(MetricKey.allCases), profile: .default))
        }
        let output = try await resolve(Identifiers(brand: "ASUS", modelLine: "Zenbook 14 OLED", confidence: .medium))
        let carbon = try #require(output.metrics[.carbon])
        // Both Zenbook 14 OLED reports (UX3405M, UX3405C), embodied only: the pipeline adds the local use phase.
        let reports = ["UX3405M", "UX3405C"].compactMap { store.asusDetail(model: $0)?.record }
        #expect(reports.count == 2)
        let embodied = reports.map { $0.totalKgCO2e * (1 - ($0.stageShares[.use] ?? 0)) }
        #expect(abs(carbon.value - embodied.reduce(0, +) / 2) < 1e-6)
        #expect(carbon.low < embodied.min()! && carbon.high > embodied.max()!)
        #expect(carbon.tier == .researchedSpec, "a line match is not the exact model's record")
        #expect(carbon.sources.count == 2 && carbon.sources.allSatisfy { $0.title.contains("same model line") })
        #expect(output.metrics[.yearlyElectricity]?.tier == .researchedSpec)

        // The exact model number still wins with its own record.
        let exact = try await resolve(Identifiers(brand: "ASUS", model: "UX3405MA", modelLine: "Zenbook 14 OLED", confidence: .high))
        #expect(exact.metrics[.carbon]?.value == 210 && exact.metrics[.carbon]?.tier == .exactRecord)

        // Too vague, a low-confidence guess, or another maker: nothing.
        #expect(try await resolve(Identifiers(brand: "ASUS", modelLine: "Zenbook", confidence: .high)).metrics.isEmpty)
        #expect(try await resolve(Identifiers(brand: "ASUS", modelLine: "Zenbook 14 OLED", confidence: .low)).metrics.isEmpty)
        #expect(try await resolve(Identifiers(brand: "Dell", modelLine: "Zenbook 14 OLED", confidence: .high)).metrics.isEmpty)
    }

    @Test func asusLineWordsMatchMarketingNames() {
        let store = ReferenceStore.bundled
        func models(_ line: String) -> [String] { store.asusDetails(modelLine: line).map(\.record.model) }
        #expect(models("ASUS Zenbook 14 OLED (2024)") == ["UX3405C", "UX3405M"])
        // The plain line takes in its OLED variants but not the Zenbook S 14 or 14X.
        #expect(models("Zenbook 14-inch") == ["UM3406K", "UX3402V", "UX3405C", "UX3405M"])
        #expect(models("Zenbook 14X OLED") == ["UX3404V"])
        #expect(models("Zenbook S 16") == ["UM5606K", "UM5606W", "UX5606S"])
        #expect(models("Vivobook 15") == ["X1504V"])
        #expect(models("Zenbook").isEmpty, "a series name alone is too vague")
        #expect(models("ROG Zephyrus G14").isEmpty)
    }

    @Test func scanCarriesTheLineFromIdentifyToResearch() async throws {
        let store = ReferenceStore.bundled
        let researcher = RecordingResearcher(values: [Self.reportCarbon])
        let cache = InMemoryResolutionCache()
        let laptopQuantities = Quantities(massKg: 1.6, screenSizeInches: 14, deviceType: "laptop")
        // Claude put the line in `model`; nothing printed backs it, so it becomes the model line.
        let mac = IdentifiedComponent(name: "Apple MacBook Pro 14-inch", category: .electronic, boundingBox: .full,
                                      identifiers: Identifiers(brand: "Apple", model: "MacBook Pro 14", confidence: .medium),
                                      quantities: laptopQuantities, estimates: [.carbon: EstimateRange(value: 300, low: 150, high: 600)])
        let zenbook = IdentifiedComponent(name: "ASUS Zenbook 14 OLED", category: .electronic, boundingBox: .full,
                                          identifiers: Identifiers(brand: "ASUS", modelLine: "Zenbook 14 OLED", confidence: .high),
                                          quantities: laptopQuantities, estimates: [.carbon: EstimateRange(value: 300, low: 150, high: 600)])
        let resolvers: [any MetricResolver] = [
            EnergyStarResolver(appliances: FakeApplianceDatabase()), ASUSPCFResolver(store: store),
            SpecResearchResolver(researcher: researcher), FactorModelResolver(store: store), EstimateResolver(),
        ]
        let pipeline = ScanPipeline(vision: FixedVision(components: [mac, zenbook]), alternatives: FakeAlternativeSuggester(),
                                    products: FakeProductDatabase(), ladder: EvidenceLadder(resolvers: resolvers, cache: cache),
                                    engine: ImpactEngine(reference: store), profile: .default)
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)

        let asked = researcher.asked.values.first { $0.brand == "Apple" }
        #expect(asked?.model == nil)
        #expect(asked?.modelLine == "MacBook Pro 14")
        // The researched embodied carbon is used (its tier joins the factor-model electricity it is combined with).
        #expect(result.components[0].metrics[.carbon]?.sources.contains { $0.title == "Laptop environmental report" } == true)
        // The Zenbook's carbon comes from its line's PCF reports, with the use phase added for the local grid.
        let embodied = try #require(store.asusDetails(modelLine: "Zenbook 14 OLED").map {
            $0.record.totalKgCO2e * (1 - ($0.record.stageShares[.use] ?? 0))
        }.max())
        let zenbookCarbon = try #require(result.components[1].metrics[.carbon])
        #expect(zenbookCarbon.tier == .researchedSpec)
        #expect(zenbookCarbon.value > embodied * 0.9)

        // A rescan of the same lines reuses the cached numbers without researching again.
        let calls = researcher.asked.values.count
        let again = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        #expect(researcher.asked.values.count == calls)
        #expect(again.components.map { $0.metrics[.carbon] } == result.components.map { $0.metrics[.carbon] })
    }
}
