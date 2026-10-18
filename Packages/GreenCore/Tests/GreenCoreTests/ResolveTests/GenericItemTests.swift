import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Unbranded items: the same kind of item gets the same numbers, and inferred model names are not trusted.
@Suite("Generic items")
struct GenericItemTests {
    private struct FixedVision: VisionIdentifier {
        var components: [IdentifiedComponent]
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
            IdentifyResponse(components: components, sceneTitle: nil)
        }
    }

    private func pipeline(_ components: [IdentifiedComponent], cache: (any ResolutionCache)? = nil) -> ScanPipeline {
        let store = ReferenceStore.bundled
        return ScanPipeline(vision: FixedVision(components: components), alternatives: FakeAlternativeSuggester(),
                            products: FakeProductDatabase(),
                            ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: store), EstimateResolver()], cache: cache),
                            engine: ImpactEngine(reference: store), profile: .default)
    }

    /// Two identify calls on the same kind of backpack: the colour differs, and so do the guessed category, mass,
    /// materials and fallback estimate, as they do between real calls.
    private let blue = IdentifiedComponent(
        name: "Blue backpack", category: .clothing, boundingBox: .full,
        identifiers: Identifiers(materials: [MaterialShare(material: "polyester", percent: 100)]),
        quantities: Quantities(massKg: 0.8), estimates: [.carbon: EstimateRange(value: 12, low: 8, high: 18)])
    private let beige = IdentifiedComponent(
        name: "Beige backpack", category: .household, boundingBox: .full,
        identifiers: Identifiers(materials: [MaterialShare(material: "nylon", percent: 70),
                                             MaterialShare(material: "polyester", percent: 30)]),
        quantities: Quantities(massKg: 1.1), estimates: [.carbon: EstimateRange(value: 20, low: 12, high: 30)])

    @Test func colourWordsDoNotChangeTheKind() {
        #expect(Identifiers.genericKey(name: "Blue backpack", category: .clothing) == "backpack")
        #expect(Identifiers.genericKey(name: "Beige Backpacks", category: .household) == "backpack")
        #expect(Identifiers.genericKey(name: "Pair of dark-grey sneakers", category: .clothing) == "sneaker")
        #expect(Identifiers.genericKey(name: "Large hiking backpack", category: .clothing) == "large hiking backpack")
        #expect(Identifiers.genericKey(name: "Glass jar", category: .packaging) == "glass jar")
        // Colour can name a different food, and electronics come from device tables.
        #expect(Identifiers.genericKey(name: "Brown rice", category: .food) == nil)
        #expect(Identifiers.genericKey(name: "Black TV", category: .electronic) == nil)
        #expect(Identifiers.genericKey(name: "Blue", category: .clothing) == nil)
        #expect(Identifiers(genericKey: "backpack").resolutionKey(category: .clothing, quantities: Quantities()) == "item:backpack")
        #expect(Identifiers(brand: "A", model: "B", genericKey: "backpack")
            .resolutionKey(category: .clothing, quantities: Quantities()) == "bm:a|b")
    }

    @Test func theGuessesAloneWouldGiveDifferentNumbers() async throws {
        let resolver = FactorModelResolver()
        func carbon(_ item: IdentifiedComponent) async throws -> Double? {
            let output = try await resolver.resolve(ResolutionRequest(component: item.makeComponent(),
                                                                      metrics: Set(MetricKey.allCases), profile: .default))
            return output.metrics[.carbon]?.value
        }
        let blueCarbon = try #require(try await carbon(blue))
        let beigeCarbon = try #require(try await carbon(beige))
        #expect(blueCarbon / beigeCarbon > 2, "clothing with garment making vs household materials only")
    }

    @Test func backpacksDifferingOnlyInColourResolveIdenticallyInOneScan() async throws {
        let result = try await pipeline([blue, beige]).run(image: Data([1]), hints: .none, mode: .photo)
        let (first, second) = (result.components[0], result.components[1])
        #expect(first.name == "Blue backpack" && second.name == "Beige backpack")
        #expect(first.category == second.category)
        #expect(!first.metrics.isEmpty)
        #expect(first.metrics == second.metrics)
        let engine = ImpactEngine(reference: ReferenceStore.bundled)
        #expect(engine.annualized(first) == engine.annualized(second))
    }

    @Test func backpacksDifferingOnlyInColourResolveIdenticallyAcrossScans() async throws {
        let cache = InMemoryResolutionCache()
        let first = try await pipeline([blue], cache: cache).run(image: Data([1]), hints: .none, mode: .photo).components[0]
        let second = try await pipeline([beige], cache: cache).run(image: Data([1]), hints: .none, mode: .photo).components[0]
        #expect(second.category == first.category)
        #expect(!first.metrics.isEmpty)
        #expect(first.metrics == second.metrics)
        #expect(first.stableSeed == second.stableSeed)
    }

    /// A backpack the photo says nothing about: only the fallback estimate, so it lands on T4.
    private let bare = IdentifiedComponent(name: "Black backpack", category: .clothing, boundingBox: .full,
                                           estimates: [.carbon: EstimateRange(value: 12, low: 8, high: 18)])

    private func scan(_ components: [IdentifiedComponent], cache: (any ResolutionCache)? = nil) async throws -> ScanResult {
        try await pipeline(components, cache: cache).run(image: Data([1]), hints: .none, mode: .photo)
    }

    @Test func theBestInformedItemOfAKindLeads() async throws {
        let result = try await scan([bare, blue])
        #expect(result.components.allSatisfy { $0.metrics[.carbon]?.tier == .factorModel })
        #expect(result.components[0].metrics == result.components[1].metrics)
    }

    @Test func aCachedEstimateDoesNotHoldBackABetterInformedItem() async throws {
        let cache = InMemoryResolutionCache()
        let first = try await scan([bare], cache: cache).components[0]
        #expect(first.metrics[.carbon]?.tier == .estimate)
        let second = try await scan([blue], cache: cache).components[0]
        #expect(second.metrics[.carbon]?.tier == .factorModel)
        // Another bare one still reads like the first.
        let third = try await scan([bare], cache: cache).components[0]
        #expect(third.metrics[.carbon] == second.metrics[.carbon])
    }

    @Test func oneDetailQuestionPerKindAndTheAnswerCoversIt() async throws {
        var other = bare
        other.name = "Grey backpack"
        let cache = InMemoryResolutionCache()
        let pipeline = pipeline([bare, other], cache: cache)
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let questions = await pipeline.specQuestions(for: result.components)
        let question = try #require(questions.first)
        #expect(questions.count == 1)
        let option = try #require(question.options.first)
        let refined = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: question.componentID,
                                                                                option: option)])
        #expect(refined.components.allSatisfy { $0.metrics[.carbon]?.tier == .factorModel })
        #expect(refined.components[0].metrics == refined.components[1].metrics)
        // The answer was about these backpacks, not every backpack: a later bare one is asked again.
        let later = try await scan([bare], cache: cache)
        #expect(later.components[0].metrics[.carbon]?.tier == .estimate)
        #expect(await pipeline.specQuestions(for: later.components).count == 1)
    }

    @Test func differentKindsAndIdentifiedItemsAreNotMerged() {
        let hiking = IdentifiedComponent(name: "Large hiking backpack", category: .clothing, boundingBox: .full,
                                         quantities: Quantities(massKg: 2))
        var branded = beige
        branded.identifiers.brand = "Acme"
        branded.identifiers.model = "BP-200"
        let prepared = ScanPipeline.withGenericKeys([blue, hiking, branded])
        #expect(prepared.map(\.identifiers.genericKey) == ["backpack", "large hiking backpack", nil])
        #expect(prepared[1].quantities.massKg == 2)
        #expect(prepared[2].quantities.massKg == 1.1)
    }

    @Test func inferredModelNamesBecomeModelLines() {
        func checked(_ model: String, line: String? = nil, confidence: IdentificationConfidence? = .high,
                     cues: String? = nil, hints: OCRHints = .none) -> Identifiers {
            let sneaker = IdentifiedComponent(name: "Sneakers", category: .clothing, boundingBox: .full,
                                              identifiers: Identifiers(brand: "Acme", model: model, modelLine: line,
                                                                       confidence: confidence, appearanceCues: cues))
            let checked = ScanPipeline.demotingUnreadModel(from: sneaker, hints: hints).identifiers
            #expect(checked.brand == "Acme")
            return checked
        }
        // A product-line name nothing on the item backs up is not a model number, but it still names the line.
        #expect(checked("Runner Max").model == nil)
        #expect(checked("Runner Max").modelLine == "Runner Max")
        #expect(checked("Runner Max 90").model == nil)
        #expect(checked("Runner Max 90", line: "Runner Max").modelLine == "Runner Max", "a stated line wins")
        // The moved line drops a repeated brand, as identify's own lines do, so both give one line key.
        #expect(checked("ACME Runner Max").modelLine == "Runner Max")
        // Identify's confidence was in a model nothing backs up: the line keeps at most medium, and only with the
        // design cues it was told from; without them it is a guess, so it is neither researched nor cached.
        #expect(checked("Runner Max", cues: "side stripe, waffle sole").confidence == .medium)
        #expect(checked("Runner Max", confidence: .medium, cues: "side stripe").confidence == .medium)
        #expect(checked("Runner Max", confidence: .low, cues: "side stripe").confidence == .low)
        #expect(checked("Runner Max", confidence: nil, cues: "side stripe").confidence == nil)
        #expect(checked("Runner Max").confidence == .low)
        #expect(checked("Runner Max").confidentModelLine == nil)
        #expect(checked("Runner Max 90", line: "Runner Max").confidence == .high, "a stated line keeps its confidence")
        // A name the on-device text contains is kept.
        #expect(checked("Runner Max 90", hints: OCRHints(textLines: ["ACME RUNNER MAX 90"])).model == "Runner Max 90")
        #expect(checked("Runner Max", hints: OCRHints(modelNumbers: ["RUNNERMAX"])).model == "Runner Max")
        #expect(checked("RM-90X", confidence: nil, hints: OCRHints(textLines: ["RM-90X"])).model == "RM-90X")
    }

    @Test func unreadCodesStayModelsOnlyWhenTranscribedWithHighConfidence() {
        func checked(_ model: String, confidence: IdentificationConfidence?, visibleText: String?) -> Identifiers {
            let laptop = IdentifiedComponent(name: "Laptop", category: .electronic, boundingBox: .full,
                                             identifiers: Identifiers(brand: "Apple", model: model, confidence: confidence,
                                                                      ocrText: visibleText))
            return ScanPipeline.demotingUnreadModel(from: laptop, hints: .none).identifiers
        }
        // Read off the item's label by identify, at high confidence: a model number.
        #expect(checked("A2681", confidence: .high, visibleText: "Model A2681 EMC 4074").model == "A2681")
        // A chip or line code looks printed but names no single product ("M2" fits many Macs), so without both it
        // is neither looked up as a model nor cached under brand|model.
        let unbacked: [(IdentificationConfidence?, String?)] = [(.medium, "M2"), (.high, nil), (nil, "M2"), (.high, "MacBook Air")]
        for (confidence, text) in unbacked {
            let ids = checked("M2", confidence: confidence, visibleText: text)
            #expect(ids.model == nil)
            #expect(ids.cacheKey == nil)
            #expect(ids.modelLine == "M2" && ids.confidence == .low, "a line guessed without cues")
        }
    }
}
