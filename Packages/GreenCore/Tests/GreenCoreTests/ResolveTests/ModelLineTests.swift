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

        // A low-confidence guess, a line without a stated confidence (Grok can return null, Claude's tool input is
        // not strictly validated), a line without a brand, or a brand alone is not researched.
        _ = try await resolve(Identifiers(brand: "Apple", modelLine: "MacBook Air", confidence: .low))
        _ = try await resolve(Identifiers(brand: "Apple", modelLine: "MacBook Air", confidence: nil))
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

        // Too vague, a low-confidence guess, no stated confidence, or another maker: nothing.
        #expect(try await resolve(Identifiers(brand: "ASUS", modelLine: "Zenbook", confidence: .high)).metrics.isEmpty)
        #expect(try await resolve(Identifiers(brand: "ASUS", modelLine: "Zenbook 14 OLED", confidence: .low)).metrics.isEmpty)
        #expect(try await resolve(Identifiers(brand: "ASUS", modelLine: "Zenbook 14 OLED", confidence: nil)).metrics.isEmpty)
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
        // Claude put the line in `model`; nothing printed backs it, so it becomes the model line (without the
        // repeated brand), still researched because identify noted the design cues it was told from.
        let mac = IdentifiedComponent(name: "Apple MacBook Pro 14-inch", category: .electronic, boundingBox: .full,
                                      identifiers: Identifiers(brand: "Apple", model: "Apple MacBook Pro 14", confidence: .high,
                                                               appearanceCues: "⌘ keys, notch, HDMI port"),
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
        #expect(asked?.confidence == .medium, "a model nothing backs up leaves the line at most medium")
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

    @Test func lineKeysHoldTheCategoryAndSize() {
        let tv = Identifiers(brand: "Samsung", modelLine: "Crystal UHD", confidence: .medium)
        #expect(tv.lineKey(category: .electronic, quantities: Quantities(screenSizeInches: 43)) == "bl:electronic|samsung|crystal uhd|43in")
        #expect(tv.lineKey(category: .electronic, quantities: Quantities(screenSizeInches: 64.5, deviceType: "tv"))
            == "bl:electronic|samsung|crystal uhd|65in")
        #expect(tv.lineKey(category: .electronic, quantities: Quantities(deviceType: "tv")) == nil, "no size, no key")
        // Without a screen, the mass stands for the size.
        let kettle = Identifiers(brand: "Smeg", modelLine: "50's Style kettle", confidence: .high)
        #expect(kettle.lineKey(category: .electronic, quantities: Quantities(massKg: 1.234)) == "bl:electronic|smeg|50's style kettle|1.2kg")
        #expect(kettle.lineKey(category: .household, quantities: Quantities(massKg: 1.234)) == "bl:household|smeg|50's style kettle|1.2kg")
        #expect(kettle.lineKey(category: .electronic, quantities: Quantities(massKg: 1.234))
            != kettle.lineKey(category: .electronic, quantities: Quantities(massKg: 1.6)))
        // A drink line comes in cans and 2 L bottles, and a pack line in many sizes: never keyed by line.
        let coke = Identifiers(brand: "Coca-Cola", modelLine: "Original Taste", confidence: .high)
        #expect(coke.lineKey(category: .food, quantities: Quantities(massKg: 0.33, servingKg: 0.33)) == nil)
        #expect(coke.lineKey(category: .packaging, quantities: Quantities(massKg: 0.015)) == nil)
        #expect(Component(name: "Coca-Cola 2 L bottle", category: .food, identifiers: coke,
                          quantities: Quantities(massKg: 2)).resolutionKey == nil)
    }

    @Test func oneLineInTwoSizesKeepsTwoSetsOfNumbers() async throws {
        let store = ReferenceStore.bundled
        let researcher = RecordingResearcher()
        let cache = InMemoryResolutionCache()
        func tv(inches: Double?) -> IdentifiedComponent {
            IdentifiedComponent(name: "Samsung Crystal UHD TV", category: .electronic, boundingBox: .full,
                                identifiers: Identifiers(brand: "Samsung", modelLine: "Crystal UHD", confidence: .medium,
                                                         appearanceCues: "Samsung logo on the bezel"),
                                quantities: Quantities(screenSizeInches: inches, deviceType: "tv"),
                                estimates: [.carbon: EstimateRange(value: 500, low: 300, high: 900)])
        }
        func scan(_ item: IdentifiedComponent) async throws -> Component {
            let resolvers: [any MetricResolver] = [
                SpecResearchResolver(researcher: researcher), FactorModelResolver(store: store), EstimateResolver(),
            ]
            let pipeline = ScanPipeline(vision: FixedVision(components: [item]), alternatives: FakeAlternativeSuggester(),
                                        products: FakeProductDatabase(), ladder: EvidenceLadder(resolvers: resolvers, cache: cache),
                                        engine: ImpactEngine(reference: store), profile: .default)
            return try await pipeline.run(image: Data([1]), hints: .none, mode: .photo).components[0]
        }
        let small = try await scan(tv(inches: 43))
        let large = try await scan(tv(inches: 65))
        #expect(researcher.asked.values.count == 2, "the 65-inch set is looked up, not served the 43-inch set's entry")
        let smallCarbon = try #require(small.metrics[.carbon]), largeCarbon = try #require(large.metrics[.carbon])
        #expect(largeCarbon.value > smallCarbon.value * 1.5)
        // The same product again still reuses its entry.
        let again = try await scan(tv(inches: 43))
        #expect(researcher.asked.values.count == 2)
        #expect(again.metrics[.carbon] == smallCarbon)
        // Without a size nothing says which set it is: it is resolved afresh and not cached.
        let entries = await cache.count
        _ = try await scan(tv(inches: nil))
        #expect(researcher.asked.values.count == 3)
        #expect(await cache.count == entries)
    }
}
