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
        #expect(Identifiers(genericKey: "backpack").resolutionKey == "item:backpack")
        #expect(Identifiers(brand: "A", model: "B", genericKey: "backpack").resolutionKey == "bm:a|b")
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

    @Test func inferredModelNamesAreDropped() {
        func model(_ model: String, hints: OCRHints = .none) -> String? {
            let sneaker = IdentifiedComponent(name: "Sneakers", category: .clothing, boundingBox: .full,
                                              identifiers: Identifiers(brand: "Acme", model: model))
            let checked = ScanPipeline.droppingUnreadModel(from: sneaker, hints: hints)
            #expect(checked.identifiers.brand == "Acme")
            return checked.identifiers.model
        }
        // A product-line name nothing on the item backs up.
        #expect(model("Runner Max") == nil)
        #expect(model("Runner Max 90") == nil)
        // A printed-looking code, or a name the on-device text contains, is kept.
        #expect(model("RM-90X") == "RM-90X")
        #expect(model("Runner Max 90", hints: OCRHints(textLines: ["ACME RUNNER MAX 90"])) == "Runner Max 90")
        #expect(model("Runner Max", hints: OCRHints(modelNumbers: ["RUNNERMAX"])) == "Runner Max")
    }
}
