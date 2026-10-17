import Foundation
import Testing
@testable import GreenCore

@Suite("GrokAnalysisClient")
struct GrokAnalysisClientTests {
    func client(_ transport: MockTransport, key: String? = "xai-key") -> GrokAnalysisClient {
        GrokAnalysisClient(configuration: .init(apiKey: key, retry: .instant()), transport: transport)
    }

    /// A completed Responses API reply whose output text is `json`.
    static func reply(_ json: String) -> MockTransport.Reply {
        let text = String(decoding: try! JSONEncoder().encode(json), as: UTF8.self)
        return .json(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":\#(text)}]}]}"#)
    }

    static let identifyJSON = #"""
        {"scene_title":"Desk setup","components":[{"name":"Dell 27-inch monitor","category":"electronic",
        "bounding_box":{"x":0.1,"y":0.1,"width":0.4,"height":0.5},
        "identifiers":{"brand":"Dell","model":null,"gtin":null,"materials":[]},
        "quantities":{"mass_kg":6.5,"screen_size_inches":27,"device_type":"monitor"},
        "default_usage":{"hours_on_per_day":8,"standby_hours_per_day":16},"deferrable_load":null,
        "fallback_estimates":[{"metric":"powerOn","value":25,"low":15,"high":40}],"needs_question":[]}]}
        """#

    @Test func identifySendsImageAndStrictSchema() async throws {
        let transport = MockTransport([Self.reply(Self.identifyJSON)])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        let response = try await client(transport).identify(image: jpeg, hints: OCRHints(), profile: UserProfile())
        #expect(response.sceneTitle == "Desk setup")
        #expect(response.components.first?.identifiers.brand == "Dell")

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.x.ai/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-key")
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(request.httpBody))
        #expect(body["model"]?.string == "grok-4.3")
        #expect(body["store"] == false)
        #expect(body["text"]?["format"]?["type"]?.string == "json_schema")
        #expect(body["text"]?["format"]?["name"]?.string == "report_components")
        #expect(body["text"]?["format"]?["strict"] == true)
        #expect(body["tools"] == nil, "identify does not search the web")
        let parts = try #require(body["input"]?.array?.first?["content"]?.array)
        #expect(parts.first?["type"]?.string == "input_image")
        #expect(parts.first?["image_url"]?.string?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(parts.last?["type"]?.string == "input_text")
    }

    @Test func invalidOutputIsSentBackOnce() async throws {
        let transport = MockTransport([Self.reply(#"{"scene_title":"Desk"}"#), Self.reply(Self.identifyJSON)])
        let response = try await client(transport).identify(image: Data(), hints: OCRHints(), profile: UserProfile())
        #expect(response.components.count == 1)
        #expect(transport.requests.count == 2)
        let retry = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests.last?.httpBody))
        #expect(retry["input"]?.array?.count == 2, "the second request carries the decode problem")
    }

    @Test func researchKeepsOnlyValuesCitingSearchedPages() async throws {
        let transport = MockTransport([.fixture("grok/research_response.json")])
        let spec = try await client(transport).research(name: "Dell U2723QE", category: .electronic,
                                                        identifiers: Identifiers(brand: "Dell", model: "U2723QE"),
                                                        metrics: [.powerOn, .standbyPower, .carbon])
        #expect(spec.values.map(\.metric) == [.powerOn], "the standby value cites a page no search returned")
        #expect(spec.values.first?.value == 25.9)
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests.first?.httpBody))
        #expect(body["tools"]?.array?.first?["type"]?.string == "web_search")
    }

    @Test func researchWithoutIdentifiersMakesNoRequest() async throws {
        let transport = MockTransport([])
        let spec = try await client(transport).research(name: "Lamp", category: .electronic,
                                                        identifiers: Identifiers(), metrics: [.powerOn])
        #expect(spec.values.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test func replyCollectsSearchSourcesAndCitations() throws {
        let response = try JSONDecoder().decode(JSONValue.self, from: Fixture.data("grok/research_response.json"))
        let reply = try GrokAnalysisClient.structuredReply(from: response)
        #expect(reply.sourceURLs.count == 3)
        #expect(reply.output["not_found"]?.array?.first?.string == "carbon")
    }

    @Test func incompleteResponsesThrow() throws {
        let response: JSONValue = ["status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"], "output": []]
        #expect(throws: GreenCoreError.invalidModelOutput("Grok response incomplete: max_output_tokens")) {
            try GrokAnalysisClient.structuredReply(from: response)
        }
    }

    @Test func missingKeyThrows() async throws {
        await #expect(throws: GreenCoreError.missingAPIKey("XAI_API_KEY")) {
            _ = try await client(MockTransport([]), key: nil).identify(image: Data(), hints: OCRHints(), profile: UserProfile())
        }
    }
}
