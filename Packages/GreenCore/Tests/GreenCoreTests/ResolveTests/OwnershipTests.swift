import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Whose items a scan shows (C2): identify's scene context and ownership calls, what the results and the footprint
/// count, and the user's "Not mine" / "Which is yours?" answers.
@Suite("Ownership and scene context")
struct OwnershipTests {
    private struct FixedVision: VisionIdentifier {
        var response: IdentifyResponse
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse { response }
    }

    private func pipeline(_ response: IdentifyResponse) -> ScanPipeline {
        let store = ReferenceStore.bundled
        return ScanPipeline(vision: FixedVision(response: response), alternatives: FakeAlternativeSuggester(),
                            products: FakeProductDatabase(),
                            ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: store), EstimateResolver()]),
                            engine: ImpactEngine(reference: store), profile: .default)
    }

    private func item(_ name: String, _ category: GreenCore.Category = .household, carbon: Double = 10,
                      likelyOwned: Bool? = nil, background: Bool? = nil) -> IdentifiedComponent {
        IdentifiedComponent(name: name, category: category, boundingBox: .full, quantities: Quantities(massKg: 1),
                            estimates: [.carbon: EstimateRange(value: carbon, low: carbon / 2, high: carbon * 2)],
                            likelyOwned: likelyOwned, background: background)
    }

    private func monitor(_ name: String = "Monitor", exclusion: Exclusion? = nil, markedOwned: Bool? = nil) -> Component {
        Component(name: name, category: .electronic,
                  metrics: [.carbon: .exact(100, unit: .kgCO2e, tier: .factorModel),
                            .lifespan: .exact(5, unit: .years, tier: .factorModel)],
                  exclusion: exclusion, markedOwned: markedOwned)
    }

    // MARK: Identify

    @Test func schemaAsksForTheSceneAndOptionalOwnership() {
        let schema = ReportComponentsTool.carbonEstimateOnlySchema
        #expect(schema["properties"]?["scene_context"]?["enum"] == ["own", "store_display", "street", "screenshot"])
        #expect(schema["required"]?.array?.compactMap(\.string).contains("scene_context") == true)
        let item = schema["properties"]?["components"]?["items"]
        #expect(item?["properties"]?["likely_owned"] != nil && item?["properties"]?["background"] != nil)
        let required = item?["required"]?.array?.compactMap(\.string) ?? []
        #expect(!required.contains("likely_owned") && !required.contains("background"),
                "omitted for the user's own things, so they cost no output")

        let system = ClaudeClient.identifySystemPrompt(vocabulary: .default, carbonEstimateOnly: true)
        #expect(system.contains("Scene and ownership"))
        #expect(system.contains("- likely_owned: false"))
        #expect(system.contains("fixtures of the place"))
        #expect(system.contains("- background: true"))
        #expect(system.contains("never report interface"))
    }

    @Test func parsesSceneAndOwnershipLeniently() throws {
        let box: JSONValue = ["x": 0.1, "y": 0.1, "width": 0.3, "height": 0.3]
        let input: JSONValue = ["scene_title": "Street", "scene_context": "Store display", "components": [
            ["name": "Gray SUV", "category": "household", "bounding_box": box, "likely_owned": false],
            ["name": "Backpack", "category": "clothing", "bounding_box": box, "background": true],
            ["name": "Sign", "category": "household", "bounding_box": box, "likely_owned": "no", "background": .null],
        ]]
        let response = try ReportComponentsTool.parse(input)
        #expect(response.sceneContext == .storeDisplay)
        #expect(response.components[0].likelyOwned == false)
        #expect(response.components[1].background == true)
        #expect(response.components[2].likelyOwned == nil, "a malformed flag is dropped, not fatal")
        #expect(try ReportComponentsTool.parse(["scene_title": "X", "scene_context": "kitchen", "components": []])
            .sceneContext == nil)
    }

    @Test func defaultExclusionFollowsTheSceneAndIdentify() {
        #expect(item("Lamp").exclusion(in: .own) == nil)
        #expect(item("Lamp").exclusion(in: nil) == nil)
        #expect(item("Stranger's car", likelyOwned: false).exclusion(in: .own) == .notOwned)
        #expect(item("Backpack", background: true).exclusion(in: .own) == .background)
        // In a store or street scene an item counts only when identify said it is likely the user's.
        #expect(item("Pint of ice cream").exclusion(in: .storeDisplay) == .notOwned)
        #expect(item("My bike", likelyOwned: true).exclusion(in: .street) == nil)
        #expect(item("Post photo", likelyOwned: true).exclusion(in: .screenshot) == .onScreen)
    }

    // MARK: Pipeline and totals

    @Test func aStreetScanCountsOnlyTheUsersThings() async throws {
        let response = IdentifyResponse(components: [
            item("Gray SUV", carbon: 9000, likelyOwned: false),
            item("Bus stop sign", carbon: 300),
            item("My bike", carbon: 100, likelyOwned: true),
        ], sceneTitle: "Street", sceneContext: .street)
        let result = try await pipeline(response).run(image: Data(), hints: .none, mode: .photo)
        #expect(result.sceneContext == .street)
        #expect(result.components.map(\.exclusion) == [.notOwned, .notOwned, nil])
        #expect(result.countedComponents.map(\.name) == ["My bike"])
        #expect(result.asksWhichIsYours)
        let bike = try #require(result.components.last)
        let bikeOnly = ImpactEngine().yearlyTotals([bike], seed: result.totalsSeed)
        #expect(result.yearlyTotals[.carbon] == bikeOnly[.carbon], "the SUV and the sign stay out of the totals")
    }

    @Test func whichIsYoursAndNotMineUpdateTotals() {
        let engine = ImpactEngine()
        var result = ScanResult(title: "Freezer", components: [monitor("A", exclusion: .notOwned),
                                                               monitor("B", exclusion: .notOwned)],
                                sceneContext: .storeDisplay)
        result.updateTotals(engine: engine)
        #expect(result.yearlyTotals[.carbon] == nil)
        #expect(result.asksWhichIsYours)

        result.markOwned(only: [result.components[0].id], engine: engine)
        #expect(!result.asksWhichIsYours, "answered once, not asked again")
        #expect(result.countedComponents.map(\.name) == ["A"])
        #expect(result.yearlyTotals[.carbon]?.value == 20)

        result.markOwned(false, componentID: result.components[0].id, engine: engine)
        #expect(result.countedComponents.isEmpty)
        #expect(result.notCountedComponents.count == 2)
        result.markOwned(nil, componentID: result.components[0].id, engine: engine)
        #expect(result.components[0].markedOwned == nil && !result.components[0].isCounted, "back to the scan's guess")
    }

    @Test func questionsAreOnlyAboutCountedItems() async throws {
        let ownQuestion = ComponentQuestion(id: "uses", question: "How often?", whyItMatters: "Frequency.",
                                            affectedMetrics: [.carbon],
                                            options: [AnswerOption(label: "Daily", field: .usesPerWeek, value: 7)])
        var car = item("Gray SUV", carbon: 9000, likelyOwned: false)
        car.needsQuestion = [ownQuestion]
        let response = IdentifyResponse(components: [car], sceneContext: .street)
        let events = EventLog()
        _ = try await pipeline(response).run(image: Data(), hints: .none, mode: .photo) { events.append($0) }
        #expect(!events.events.contains { if case .questionsNeeded = $0 { true } else { false } })
        #expect(!events.events.contains { if case .specQuestionsNeeded = $0 { true } else { false } })
    }

    @Test func excludedItemsGetNoSwaps() async throws {
        var result = ScanResult(title: "Desk", components: [monitor("Mine"), monitor("Background bag", exclusion: .background)])
        result = try await pipeline(IdentifyResponse(components: [])).suggestAlternatives(for: result)
        #expect(!result.components[0].alternatives.isEmpty)
        #expect(result.components[1].alternatives.isEmpty)
    }

    @Test func anItemCountedLaterGetsItsOwnSwaps() async throws {
        let pipeline = pipeline(IdentifyResponse(components: []))
        var result = ScanResult(title: "Desk", components: [monitor("Mine"), monitor("Bag", exclusion: .background)])
        result = try await pipeline.suggestAlternatives(for: result)
        let kept = result.components[0].alternatives
        // "It's mine" on the bag after the swaps came back: only the bag is asked about.
        result.markOwned(true, componentID: result.components[1].id, engine: ImpactEngine())
        let updated = try await pipeline.suggestAlternatives(forItems: [result.components[1].id], in: result)
        #expect(!updated.components[1].alternatives.isEmpty)
        #expect(updated.components[0].alternatives == kept, "the other items keep their swaps")
        #expect(try await pipeline.suggestAlternatives(forItems: [], in: result) == result)
    }

    // MARK: Footprint and results order

    @Test func theFootprintCountsOnlyTheUsersOwnItems() {
        let engine = ImpactEngine()
        let street = ScanResult(title: "Street", components: [monitor("Neighbour's AC", exclusion: .notOwned),
                                                              monitor("Stock", markedOwned: false),
                                                              monitor("Mine")])
        #expect(ScannedFootprint.from(scans: [street], engine: engine).yearly[.carbon] == 20)
        let claimed = ScanResult(title: "Post", components: [monitor("Seen", exclusion: .onScreen),
                                                             monitor("Bought", exclusion: .onScreen, markedOwned: true)])
        #expect(ScannedFootprint.from(scans: [claimed], engine: engine).yearly[.carbon] == 20)
        #expect(claimed.totaledComponents.count == 2, "seen on screen: shown as if bought, not in the footprint")
    }

    @Test func notCountedItemsAreNumberedLast() {
        let big = monitor("Background car", exclusion: .notOwned)
        var small = monitor("Notebook")
        small.metrics[.carbon] = .exact(1, unit: .kgCO2e, tier: .factorModel)
        let breakdown = ScanBreakdown(components: [big, small], notCounted: [big.id])
        #expect(breakdown.number(of: small) == 1)
        #expect(breakdown.number(of: big) == 2)
        #expect(ScanBreakdown(components: [big, small]).number(of: big) == 1)
    }

    @Test func scansFromOlderBuildsCountEverything() throws {
        let result = ScanResult(title: "Desk", components: [monitor()], sceneContext: .street)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        json["sceneContext"] = nil
        let decoded = try JSONDecoder().decode(ScanResult.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.sceneContext == nil)
        #expect(decoded.components[0].isCounted)
        let roundTrip = try JSONDecoder().decode(ScanResult.self, from: JSONEncoder().encode(result))
        #expect(roundTrip.sceneContext == .street)
    }

    // MARK: Cache

    @Test func aStaleCachedClothingHelmetIsNotTakenBack() {
        let helmet = Component(name: "Bike helmet", category: .household)
        var cached = helmet
        cached.category = .clothing
        #expect(!ScanPipeline.acceptsCached(cached, for: helmet))
        let backpack = Component(name: "Beige backpack", category: .household)
        var cachedBackpack = backpack
        cachedBackpack.category = .clothing
        #expect(ScanPipeline.acceptsCached(cachedBackpack, for: backpack), "kinds still share their category")
    }
}

