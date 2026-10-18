import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Identify's classification guards and optional fields: non-textile accessories (C1), the prompt's identify fixes
/// (C5), the item's pin anchor and its canonical kind.
@Suite("Identify fields and classification")
struct IdentifyFieldsTests {
    private struct FixedVision: VisionIdentifier {
        var components: [IdentifiedComponent]
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
            IdentifyResponse(components: components)
        }
    }

    private func pipeline(_ components: [IdentifiedComponent] = []) -> ScanPipeline {
        let store = ReferenceStore.bundled
        return ScanPipeline(vision: FixedVision(components: components), alternatives: FakeAlternativeSuggester(),
                            products: FakeProductDatabase(),
                            ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: store), EstimateResolver()]),
                            engine: ImpactEngine(reference: store), profile: .default)
    }

    private func item(_ name: String, _ category: GreenCore.Category = .clothing, kind: String? = nil) -> IdentifiedComponent {
        IdentifiedComponent(name: name, category: category, boundingBox: .full, kind: kind)
    }

    // MARK: C1

    @Test func eyewearAndHelmetsAreNeverClothing() {
        let pipeline = pipeline()
        for name in ["Eyeglasses", "Black sunglasses", "Reading glasses (left)", "Bike helmet", "Ski goggles",
                     "Wristwatch", "Silver necklace", "Folded umbrella"] {
            #expect(pipeline.reclassified(item(name)).category == .household, "\(name)")
        }
        // The kind decides when the name does not say it.
        #expect(pipeline.reclassified(item("Giro Syntax", kind: "helmet")).category == .household)
        // Fabric stays clothing, and other categories are left alone.
        for name in ["Cotton T-shirt", "Blue backpack", "Running shoes", "Wool beanie"] {
            #expect(pipeline.reclassified(item(name)).category == .clothing, "\(name)")
        }
        #expect(pipeline.reclassified(item("Drinking glasses", .household)).category == .household)
        #expect(pipeline.reclassified(item("Glass jar", .packaging)).category == .packaging)
    }

    @Test func aHelmetScanResolvesWithoutFabricMetrics() async throws {
        let helmet = IdentifiedComponent(
            name: "Bike helmet", category: .clothing, boundingBox: .full,
            identifiers: Identifiers(materials: [MaterialShare(material: "polycarbonate", percent: 30),
                                                 MaterialShare(material: "eps", percent: 70)]),
            quantities: Quantities(massKg: 0.3), estimates: [.carbon: EstimateRange(value: 4, low: 2, high: 8)])
        let result = try await pipeline([helmet]).run(image: Data(), hints: .none, mode: .photo)
        let component = try #require(result.components.first)
        #expect(component.category == .household)
        #expect(component.metrics[.land] == nil, "land is a clothing (fibre) metric")
    }

    @Test func promptRoutesAccessoriesAndTightensIdentify() {
        let system = ClaudeClient.identifySystemPrompt(vocabulary: .default, carbonEstimateOnly: true)
        // C1: eyewear and helmets are household.
        #expect(system.contains("eyewear, helmets, watches"))
        #expect(!system.contains("worn accessories are `clothing`"))
        // C5: every food, materials from what is seen, paper sizes, tight boxes without hands.
        #expect(system.contains("List every distinct food you can see"))
        #expect(system.contains("sauces and dressings"))
        #expect(system.contains("Judge materials from what you see"))
        #expect(system.contains("quarter sheet 4.25x5.5 in"))
        #expect(system.contains("not the hand holding it"))
        #expect(system.contains("one box per item"))
        #expect(system.contains("- anchor: for every item"))
        #expect(system.contains("- kind: for items other than food and electronics"))
    }

    // MARK: Schema and parsing

    @Test func schemaOffersAnOptionalAnchorAndKind() {
        let item = ReportComponentsTool.carbonEstimateOnlySchema["properties"]?["components"]?["items"]
        let fields = item?["properties"]
        #expect(fields?["anchor"]?["properties"]?["x"] != nil)
        #expect(fields?["anchor"]?["required"] == ["x", "y"])
        #expect(fields?["kind"] != nil)
        let required = item?["required"]?.array?.compactMap(\.string) ?? []
        #expect(!required.contains("anchor") && !required.contains("kind"), "optional: older answers still decode")
        #expect(ReportComponentsTool.slimDefinition["input_schema"]?["properties"]?["components"]?["items"]?["properties"]?["anchor"] != nil)
        // No brand or product names a fast model could copy.
        let descriptions = [fields?["anchor"]?["description"], fields?["kind"]?["description"]].compactMap { $0?.string }
        #expect(descriptions.count == 2)
        for word in ["Dell", "Apple", "backpack", "SUV"] { #expect(!descriptions.contains { $0.contains(word) }) }
    }

    @Test func parsesAnchorAndKindAndDropsMalformedOnes() throws {
        func component(_ extra: [String: JSONValue]) -> JSONValue {
            var fields: [String: JSONValue] = ["name": "Blue backpack (partly visible)", "category": "clothing",
                                               "bounding_box": ["x": 0.1, "y": 0.2, "width": 0.5, "height": 0.4]]
            fields.merge(extra) { _, new in new }
            return .object(fields)
        }
        let input: JSONValue = ["scene_title": "Desk", "components": [
            component(["anchor": ["x": 0.3, "y": 1.4], "kind": " backpack "]),
            component(["anchor": [0.3, 0.4], "kind": 7]),
            component(["anchor": .null, "kind": .null]),
        ]]
        let response = try ReportComponentsTool.parse(input)
        #expect(response.components[0].anchor == NormalizedPoint(x: 0.3, y: 1))
        #expect(response.components[0].kind == "backpack")
        #expect(response.components[0].makeComponent().anchor == NormalizedPoint(x: 0.3, y: 1))
        #expect(response.components[1].anchor == nil && response.components[1].kind == nil, "malformed fields are dropped")
        #expect(response.components[2].anchor == nil && response.components[2].kind == nil)
    }

    // MARK: Kind

    @Test func theKindIsPreferredOverTheNameForGenericKeys() {
        #expect(Identifiers.genericKey(name: "Navy daypack with laptop sleeve", category: .clothing, kind: "backpack")
            == "backpack")
        #expect(Identifiers.genericKey(name: "Gray Kia Sorento", category: .household, brand: "Kia", kind: "SUVs")
            == "kia|suv", "normalized by the same rules, brand prefix kept")
        #expect(Identifiers.genericKey(name: "Blue backpack", category: .clothing, kind: "item") == "backpack",
                "a kind with no words left falls back to the name")
        #expect(Identifiers.genericKey(name: "Rice bowl", category: .food, kind: "rice") == nil)
    }

    @Test func itemsOfOneKindShareNumbersWhateverTheirNames() {
        let first = IdentifiedComponent(name: "Navy daypack", category: .clothing, boundingBox: .full,
                                        quantities: Quantities(massKg: 0.8), kind: "backpack")
        let second = IdentifiedComponent(name: "School bag with patches", category: .clothing, boundingBox: .full,
                                         kind: "backpack")
        let keyed = ScanPipeline.withGenericKeys([first, second])
        #expect(keyed.map(\.identifiers.genericKey) == ["backpack", "backpack"])
        #expect(keyed[1].quantities.massKg == 0.8)
    }

    // MARK: Anchor

    @Test func pinsUseIdentifysPointWhenItIsOnOrNearTheBox() {
        let box = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        // A spoon lying across a loose box: the point is on the spoon, the centre is not.
        #expect(PinLayout.anchor(box: box, point: NormalizedPoint(x: 0.25, y: 0.55)) == NormalizedPoint(x: 0.25, y: 0.55))
        #expect(PinLayout.anchor(box: box, point: NormalizedPoint(x: 0.65, y: 0.3)) == NormalizedPoint(x: 0.65, y: 0.3),
                "just outside a loose box still counts")
        #expect(PinLayout.anchor(box: box, point: NormalizedPoint(x: 0.95, y: 0.95)) == NormalizedPoint(x: 0.4, y: 0.4),
                "far from the box is a slip: back to the centre")
        #expect(PinLayout.anchor(box: box, point: nil) == NormalizedPoint(x: 0.4, y: 0.4))
        let component = Component(name: "Spoon", category: .household, boundingBox: box,
                                  anchor: NormalizedPoint(x: 0.25, y: 0.55))
        #expect(component.pinAnchor == NormalizedPoint(x: 0.25, y: 0.55))
    }

    @Test func scansSavedWithoutAnAnchorStillLoad() throws {
        let component = Component(name: "Mug", category: .household)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(component)) as? [String: Any])
        json["anchor"] = nil
        let decoded = try JSONDecoder().decode(Component.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.anchor == nil)
        #expect(decoded.pinAnchor == NormalizedPoint(x: 0.5, y: 0.5))
    }
}
