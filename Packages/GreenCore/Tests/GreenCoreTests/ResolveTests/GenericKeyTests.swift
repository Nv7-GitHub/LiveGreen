import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Generic kinds read alike however identify words the name, and two makers' items never share one kind. The names
/// are ones identify returned for the testing_images photos.
@Suite("Generic item keys")
struct GenericKeyTests {
    private func key(_ name: String, _ category: GreenCore.Category = .household, brand: String? = nil) -> String? {
        Identifiers.genericKey(name: name, category: category, brand: brand)
    }

    @Test func plurals() {
        #expect(key("Eyeglasses (pair)", .clothing) == "eyeglass")
        #expect(key("Eyeglass", .clothing) == "eyeglass")
        #expect(key("Cardboard boxes", .packaging) == "cardboard box")
        #expect(key("Cardboard box", .packaging) == "cardboard box")
        #expect(key("AA batteries") == "aa battery")
        #expect(key("Steak knives") == "steak knife")
        #expect(key("Hoodies", .clothing) == "hoodie")
        #expect(key("Denim jeans", .clothing) == "denim jeans")
        #expect(key("Glass", .packaging) == "glass")
    }

    @Test func photoPositionAndVisibilityAreNotPartOfTheKind() {
        #expect(key("White electric sedan (background)") == "electric sedan")
        #expect(key("Electric sedan background") == "electric sedan")
        #expect(key("Black bicycle with basket (left)") == "bicycle with basket")
        #expect(key("Bicycle with basket left") == "bicycle with basket")
        #expect(key("Commuter bicycle (foreground, silver frame)") == "commuter bicycle")
        #expect(key("Gray SUV") == "suv")
        #expect(key("Grey SUV (partially visible)") == "suv")
        #expect(key("Gray SUV (partial") == "suv", "an unclosed bracket runs to the end")
    }

    @Test func sizesAndPrintedAmountsAreNotPartOfTheKind() {
        #expect(key("Compact SUV") == "suv")
        #expect(key("Large hiking backpack", .clothing) == "hiking backpack")
        #expect(key("Paper flyer (yellow, half-sheet)", .packaging) == "paper flyer")
        #expect(key("Paper flyer, half sheet", .packaging) == "paper flyer")
        #expect(key("Candy snack-size plastic wrappers", .packaging) == "candy plastic wrapper")
        #expect(key("16 oz plastic cup", .packaging) == "plastic cup")
        #expect(key("Stain remover spray 22 fl oz") == "stain remover spray")
        #expect(key("Size 10 sneakers", .clothing) == "sneaker")
        #expect(key("Sedan, full-size") == "sedan")
    }

    @Test func lidVariantsAreOneKind() {
        let names = ["Clear plastic cup with dome lid", "Plastic cups with domed lids", "Clear plastic cups with lids",
                     "Plastic cup and lid", "Plastic cup w/ lid", "Plastic cup with sealed lid"]
        for name in names {
            #expect(key(name, .packaging) == "plastic cup with lid", "\(name)")
        }
        #expect(key("Plastic drinking straw", .packaging) == key("Plastic straws", .packaging))
        #expect(key("Clear plastic cup with plastic spoon", .packaging) == "plastic cup with plastic spoon")
    }

    @Test func leftoverJoiningWordsAndEmptyHeadsAreHandled() {
        #expect(key("Black and white sneakers", .clothing) == "sneaker")
        #expect(key("Large, white mug") == "mug", "nothing before the comma names the kind, so the whole name is used")
        #expect(key("Levi's jeans", .clothing) == "levi jeans")
        #expect(key("Blue (left)", .clothing) == nil)
    }

    @Test func durablesIncludeTheBrandAndPackagingDoesNot() {
        #expect(key("Compact SUV", brand: "Kia") == "kia|suv")
        #expect(key("White Honda compact SUV", brand: "Honda") == "honda|suv")
        #expect(key("Compact SUV", brand: "Honda") == "honda|suv", "the brand counts once, in or out of the name")
        #expect(key("Shout Triple-Acting stain remover spray, 22 fl oz", brand: "Shout")
            == "shout|triple acting stain remover spray")
        #expect(key("Spiral notebook (Five Star)", brand: "Mead") == key("Mead spiral notebook", brand: "Mead"))
        #expect(key("Hoodie", .clothing, brand: "The North Face") == "the north face|hoodie")
        #expect(key("Hand soap pump", .personalCare, brand: "Dove") == "dove|hand soap pump")
        #expect(key("Chip bag", .packaging, brand: "Lay's") == "chip bag")
        #expect(key("Compact SUV", brand: "Unknown") == "suv", "a placeholder is no brand")
        #expect(key("Shout", brand: "Shout") == nil, "the brand alone names no kind")
        #expect(Identifiers(brand: "Kia", genericKey: "kia|suv").resolutionKey(category: .household, quantities: Quantities())
            == "item:kia|suv")
    }

    // MARK: The pipeline

    private struct FixedVision: VisionIdentifier {
        var components: [IdentifiedComponent]
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
            IdentifyResponse(components: components, sceneTitle: nil)
        }
    }

    private func scan(_ components: [IdentifiedComponent], cache: any ResolutionCache) async throws -> ScanResult {
        let store = ReferenceStore.bundled
        return try await ScanPipeline(vision: FixedVision(components: components), alternatives: FakeAlternativeSuggester(),
                                      products: FakeProductDatabase(),
                                      ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: store), EstimateResolver()],
                                                             cache: cache),
                                      engine: ImpactEngine(reference: store), profile: .default)
            .run(image: Data([1]), hints: .none, mode: .photo)
    }

    private func car(_ name: String, brand: String, massKg: Double, steel: Double) -> IdentifiedComponent {
        IdentifiedComponent(name: name, category: .household, boundingBox: .full,
                            identifiers: Identifiers(brand: brand, materials: [MaterialShare(material: "steel", percent: steel),
                                                                               MaterialShare(material: "aluminium", percent: 100 - steel)]),
                            quantities: Quantities(massKg: massKg),
                            estimates: [.carbon: EstimateRange(value: 9000, low: 6000, high: 14000)])
    }

    /// A Kia scanned first must not give a later Honda its numbers, while a later Kia of the same kind still does.
    @Test func twoBrandsOfOneKindDoNotShareNumbers() async throws {
        let cache = InMemoryResolutionCache()
        let kia = try await scan([car("Compact SUV", brand: "Kia", massKg: 1550, steel: 80)], cache: cache).components[0]
        let honda = try await scan([car("White compact SUV", brand: "Honda", massKg: 1300, steel: 60)], cache: cache).components[0]
        #expect(kia.resolutionKey == "item:kia|suv")
        #expect(honda.resolutionKey == "item:honda|suv")
        #expect(honda.metrics[.carbon] != kia.metrics[.carbon])
        let laterKia = try await scan([car("Grey compact SUV (background)", brand: "KIA", massKg: 1700, steel: 70)],
                                      cache: cache).components[0]
        #expect(laterKia.metrics == kia.metrics)
    }

    @Test func twoBrandsInOneScanAreNotMerged() {
        let prepared = ScanPipeline.withGenericKeys([car("Compact SUV", brand: "Kia", massKg: 1550, steel: 80),
                                                     car("Compact SUV", brand: "Honda", massKg: 1300, steel: 60)])
        #expect(prepared.map(\.identifiers.genericKey) == ["kia|suv", "honda|suv"])
        #expect(prepared[1].quantities.massKg == 1300)
    }
}
