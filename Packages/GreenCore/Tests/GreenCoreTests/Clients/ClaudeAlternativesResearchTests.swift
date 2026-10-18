import Foundation
import Testing
@testable import GreenCore

@Suite("ClaudeClient alternatives and research")
struct ClaudeAlternativesResearchTests {
    static let burger = Component(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Beef burger",
                                  category: .food, quantities: Quantities(massKg: 0.25, foodGroup: "beef"),
                                  metrics: [.carbon: .exact(7.2, unit: .kgCO2e, tier: .factorModel)],
                                  usage: UsageProfile(servingsPerWeek: 2))
    static let monitor = Component(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Dell monitor",
                                   category: .electronic, identifiers: Identifiers(brand: "Dell", model: "E2225H"))
    static let lamp = Component(name: "Desk lamp", category: .electronic)

    func client(_ transport: MockTransport) -> ClaudeClient {
        ClaudeClient(configuration: .init(apiKey: "sk-test", retry: .instant()), transport: transport)
    }

    // MARK: Alternatives

    @Test func alternativesRequestListsComponentsByID() async throws {
        let transport = MockTransport([.fixture("claude/alternatives_tool_use.json")])
        _ = try await client(transport).suggestAlternatives(for: [Self.burger, Self.monitor], profile: .default)

        let body = try #require(transport.requests.first?.jsonBody)
        #expect(body["tools"]?.array?.first?["name"]?.string == "suggest_alternatives")
        #expect(body["system"]?.array?.first?["text"]?.string?.contains("Do not suggest smart plugs") == true)
        let text = try #require(body["messages"]?.array?.first?["content"]?.array?.first?["text"]?.string)
        #expect(text.contains("11111111-1111-1111-1111-111111111111"))
        #expect(!text.contains("current_metrics"), "resolved numbers are not sent, so swaps are not scaled from them")
        #expect(text.contains("\"food_group\":\"beef\""))
        #expect(transport.requests.first?.timeoutInterval == 45)
    }

    @Test func decodesAlternatives() async throws {
        let transport = MockTransport([.fixture("claude/alternatives_tool_use.json")])
        let suggestions = try await client(transport).suggestAlternatives(for: [Self.burger, Self.monitor, Self.lamp],
                                                                          profile: .default)
        #expect(suggestions.map(\.componentID) == [Self.burger.id, Self.monitor.id], "unknown ids ignored, order kept")

        let burgerAlternatives = suggestions[0].alternatives
        #expect(burgerAlternatives.count == 3, "capped at three")
        #expect(burgerAlternatives[0].name == "Lentil burger")
        #expect(burgerAlternatives[0].practicality == Practicality(cost: .lower, effort: .easy))
        #expect(burgerAlternatives[0].quantities.foodGroup == "beans")
        #expect(burgerAlternatives[0].fallbackEstimates.keys.sorted { $0.rawValue < $1.rawValue } == [.carbon])
        #expect(burgerAlternatives[1].practicality.effort == .easy, "case-insensitive enums")
        #expect(burgerAlternatives[1].usage == Self.burger.usage, "missing usage inherits the original's")

        #expect(burgerAlternatives[0].looksDifferent == nil, "left out: judged from the swap itself")
        let monitorSwap = try #require(suggestions[1].alternatives.first)
        #expect(monitorSwap.identifiers.model == "P2425H")
        #expect(monitorSwap.kind == .product)
        #expect(monitorSwap.condition == .refurbished, "a condition left out is read from the name")
        #expect(!monitorSwap.isReusable)
        #expect(monitorSwap.lifespanYears == nil)
    }

    @Test func reusablesAreFiledAsHouseholdWithTheirLifespan() throws {
        let cup = Component(id: UUID(), name: "Paper cup", category: .packaging, usage: UsageProfile(usesPerWeek: 5))
        let input: JSONValue = ["suggestions": [[
            "component_id": .string(cup.id.uuidString),
            "alternatives": [[
                "name": "Steel tumbler", "category": "packaging", "rationale": "Reused for years.",
                "cost": "higher", "effort": "easy", "condition": "new", "reusable": true, "lifespan_years": 4,
                "looks_different": true,
                "identifiers": ["brand": nil, "model": nil, "gtin": nil,
                                "materials": [["material": "stainless_steel", "percent": 100]]],
                "quantities": ["mass_kg": 0.3], "usage": nil,
                "fallback_estimates": [["metric": "lifespan", "value": 4, "low": 2, "high": 8],
                                       ["metric": "carbon", "value": 2, "low": 1, "high": 3]],
            ]],
        ]]]
        let swap = try #require(try SuggestAlternativesTool.parse(input, components: [cup]).first?.alternatives.first)
        #expect(swap.category == .household, "a reusable is a durable, not 156 cups a year")
        #expect(swap.isReusable)
        #expect(swap.lifespanYears == 4)
        #expect(swap.fallbackEstimates[.lifespan]?.value == 4, "kept as a household metric")
        #expect(swap.usage == cup.usage)
        #expect(swap.looksDifferent == true)
    }

    @Test func conditionFromTheName() {
        #expect(Alternative.Condition(name: "Buy a used compact SUV") == .used)
        #expect(Alternative.Condition(name: "Second-hand backpack") == .used)
        #expect(Alternative.Condition(name: "Refurbished Dell monitor") == .refurbished)
        #expect(Alternative.Condition(name: "Window AC used an hour less a day") == .new)
        #expect(Alternative.Condition(name: "Reusable glass jar") == .new)
    }

    @Test func swapsSavedBeforeTheNewFieldsDecode() throws {
        let saved = Alternative(name: "Lentil burger", category: .food, rationale: "Plant protein.")
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        json["condition"] = nil
        json["isReusable"] = nil
        let decoded = try JSONDecoder().decode(Alternative.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == saved)
    }

    @Test func noComponentsSkipsTheCall() async throws {
        let transport = MockTransport([])
        #expect(try await client(transport).suggestAlternatives(for: [], profile: .default).isEmpty)
        #expect(transport.requests.isEmpty)
    }

    // MARK: Research

    @Test func researchRequestDeclaresServerTools() async throws {
        let transport = MockTransport([.fixture("claude/research_tool_use.json")])
        _ = try await client(transport).research(name: "Dell monitor", category: .electronic,
                                                 identifiers: Self.monitor.identifiers,
                                                 metrics: [.powerOn, .standbyPower, .water])
        let request = try #require(transport.requests.first)
        #expect(request.timeoutInterval == 45)
        let tools = try #require(request.jsonBody?["tools"]?.array)
        #expect(tools.map { $0["name"]?.string } == ["report_specs", "web_search", "web_fetch"])
        #expect(tools[1]["type"]?.string == "web_search_20260209")
        #expect(tools[2]["type"]?.string == "web_fetch_20260209")
        #expect(tools[1]["max_uses"]?.double == 4)
        let metricEnum = tools[0]["input_schema"]?["properties"]?["values"]?["items"]?["properties"]?["metric"]?["enum"]
        #expect(metricEnum == ["powerOn", "standbyPower"], "inapplicable metrics are not requested")
        #expect(request.jsonBody?["output_config"]?["effort"]?.string == "medium")
    }

    @Test func keepsOnlyCitedRetrievedValues() async throws {
        let transport = MockTransport([.fixture("claude/research_pause_turn.json"), .fixture("claude/research_tool_use.json")])
        let spec = try await client(transport).research(
            name: "Dell monitor", category: .electronic, identifiers: Self.monitor.identifiers,
            metrics: [.powerOn, .standbyPower, .plasticMass, .lifespan, .repairability, .carbon])

        // pause_turn is resumed by replaying the assistant turn with no new user message.
        let resumed = try #require(transport.requests.last?.jsonBody?["messages"]?.array)
        #expect(resumed.count == 2)
        #expect(resumed[1]["role"]?.string == "assistant")

        #expect(spec.values.map(\.metric) == [.powerOn, .plasticMass])
        let power = try #require(spec.measured[.powerOn])
        #expect(power.value == 10.9)
        #expect(power.tier == .researchedSpec)
        #expect(abs(power.low - 9.81) < 1e-9, "±10% when the source gives no range")
        #expect(power.sources.first?.quote == "10.9 W (On Mode),   26 W (Max)")
        #expect(power.sources.first?.url?.host() == "dell.com")
    }

    @Test func researchWithoutIdentifiersSkipsTheCall() async throws {
        let transport = MockTransport([])
        let spec = try await client(transport).research(name: "Lamp", category: .electronic, identifiers: Identifiers(),
                                                        metrics: [.powerOn])
        #expect(spec.values.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test func sourceIndexVerifiesQuotesAgainstFetchedText() throws {
        let transcript = try JSONDecoder().decode(MessagesResponse.self, from: Fixture.data("claude/research_tool_use.json")).content
        let index = ResearchSourceIndex(transcript: transcript)
        let page = URL(string: "https://www.dell.com/support/manuals/en-us/dell-e2225h-monitor/e2225h_ug/specifications#power")!
        #expect(index.supports(quote: "Power consumption: 0.3 W (Off Mode)", from: page))
        #expect(index.supports(quote: "0.3 W (Off Mode) … 10.9 W (On Mode)", from: page), "ellipsis-separated fragments")
        #expect(!index.supports(quote: "12 W (On Mode)", from: page))
        #expect(!index.supports(quote: "anything", from: URL(string: "https://example.com")!))
    }
}
