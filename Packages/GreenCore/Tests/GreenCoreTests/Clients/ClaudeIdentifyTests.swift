import Foundation
import Testing
@testable import GreenCore

@Suite("ClaudeClient identify")
struct ClaudeIdentifyTests {
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    static let hints = OCRHints(gtins: ["5449000000996"], modelNumbers: ["E2225H"], wattages: [65], textLines: ["DELL"])

    func client(_ transport: MockTransport, model: ClaudeModel = .opus) -> ClaudeClient {
        ClaudeClient(configuration: .init(apiKey: "sk-test", model: model, retry: .instant()), transport: transport)
    }

    @Test func buildsMessagesRequest() async throws {
        let transport = MockTransport([.fixture("claude/identify_tool_use.json")])
        _ = try await client(transport, model: .sonnet).identify(image: Self.jpeg, hints: Self.hints, profile: .default)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(request.timeoutInterval == 30)

        let body = try #require(request.jsonBody)
        #expect(body["model"]?.string == "claude-sonnet-5-5")
        #expect(body["fallbacks"]?.string == "default")
        #expect(body["tool_choice"]?["type"]?.string == "auto")
        #expect(body["output_config"]?["effort"]?.string == "low")
        // Sampling parameters and thinking budgets are rejected by these models.
        #expect(body["temperature"] == nil)
        #expect(body["thinking"] == nil)
        #expect(body["tools"]?.array?.first?["name"]?.string == "report_components")

        let system = try #require(body["system"]?.array?.first?["text"]?.string)
        #expect(system.contains("You do NOT calculate environmental impacts"))
        #expect(system.contains("- `food`: carbon, water, land"))
        #expect(body["system"]?.array?.first?["cache_control"]?["type"]?.string == "ephemeral")

        let content = try #require(body["messages"]?.array?.first?["content"]?.array)
        #expect(content[0]["type"]?.string == "image")
        #expect(content[0]["source"]?["media_type"]?.string == "image/jpeg")
        #expect(content[0]["source"]?["data"]?.string == Self.jpeg.base64EncodedString())
        let text = try #require(content[1]["text"]?.string)
        #expect(text.contains("Barcodes (GTIN): 5449000000996"))
        #expect(text.contains("Wattages: 65 W"))
        #expect(text.contains("User profile: Lives in MA, US"))
    }

    @Test func decodesAndSanitizesComponents() async throws {
        let transport = MockTransport([.fixture("claude/identify_tool_use.json")])
        let response = try await client(transport).identify(image: Self.jpeg, hints: .none, profile: .default)

        #expect(response.sceneTitle == "Desk setup")
        #expect(response.components.count == 3)

        let monitor = response.components[0]
        #expect(monitor.category == .electronic)
        #expect(monitor.identifiers.brand == "Dell")
        #expect(monitor.identifiers.model == "E2225H")
        #expect(monitor.identifiers.ocrText == "DELL E2225H")
        #expect(monitor.identifiers.materials.count == 3)
        #expect(monitor.quantities.screenSizeInches == 21.5)
        #expect(monitor.quantities.deviceType == "monitor")
        #expect(monitor.defaultUsage?.hoursOnPerDay == 8)
        #expect(monitor.estimates[.carbon] == EstimateRange(value: 300, low: 180, high: 500))
        #expect(monitor.estimates[.water] == nil, "water does not apply to electronics")
        #expect(monitor.needsQuestion.first?.options.last?.field == .hoursOnPerDay)

        let charger = response.components[1]
        #expect(charger.category == .electronic, "'Electronics' is accepted")
        #expect(charger.deferrableLoad == .laptopCharger)
        #expect(charger.identifiers.gtin == nil, "non-numeric GTIN dropped")
        #expect(abs(charger.boundingBox.width - 0.2) < 1e-9, "box clamped into the frame")
        #expect(charger.estimates[.carbon] == EstimateRange(value: 5, low: 2, high: 8))
        #expect(charger.needsQuestion.isEmpty, "question without options dropped")

        let cup = response.components[2]
        #expect(cup.identifiers.gtin == "5449000000996")
        #expect(cup.makeComponent().fallbackEstimates[.carbon]?.value == 0.11)
    }

    @Test func nudgesWhenClaudeAnswersInText() async throws {
        let transport = MockTransport([.fixture("claude/identify_text_only.json"), .fixture("claude/identify_tool_use.json")])
        let response = try await client(transport).identify(image: Self.jpeg, hints: .none, profile: .default)
        #expect(response.components.count == 3)

        let messages = try #require(transport.requests.last?.jsonBody?["messages"]?.array)
        #expect(messages.count == 3)
        #expect(messages[1]["role"]?.string == "assistant")
        // The assistant turn, including its thinking block, is replayed unchanged.
        #expect(messages[1]["content"]?.array?.first?["signature"]?.string == "EqQBtext")
        #expect(messages[2]["content"]?.array?.first?["text"]?.string?.contains("report_components") == true)
    }

    @Test func returnsSchemaErrorsToClaude() async throws {
        let transport = MockTransport([.fixture("claude/identify_invalid_category.json"), .fixture("claude/identify_tool_use.json")])
        _ = try await client(transport).identify(image: Self.jpeg, hints: .none, profile: .default)

        let followUp = try #require(transport.requests.last?.jsonBody?["messages"]?.array?.last?["content"]?.array?.first)
        #expect(followUp["type"]?.string == "tool_result")
        #expect(followUp["tool_use_id"]?.string == "toolu_01Bad")
        #expect(followUp["is_error"]?.bool == true)
        #expect(followUp["content"]?.string?.contains("plant") == true)
    }

    @Test func retriesMaxTokensWithLargerBudget() async throws {
        let transport = MockTransport([.fixture("claude/max_tokens.json"), .fixture("claude/identify_tool_use.json")])
        _ = try await client(transport).identify(image: Self.jpeg, hints: .none, profile: .default)
        let budgets = transport.requests.compactMap { $0.jsonBody?["max_tokens"]?.double }
        #expect(budgets == [16_000, 32_000])
        #expect(transport.requests.last?.jsonBody?["messages"]?.array?.count == 1, "truncated turn is not replayed")
    }

    @Test func refusalThrows() async throws {
        let transport = MockTransport([.fixture("claude/refusal.json")])
        await #expect(throws: GreenCoreError.invalidModelOutput("Claude declined the request (cyber).")) {
            _ = try await client(transport).identify(image: Self.jpeg, hints: .none, profile: .default)
        }
    }

    @Test func retriesOverloadedAndRateLimitHonoringRetryAfter() async throws {
        let delays = Recorder<Double>()
        let transport = MockTransport([
            .fixture("claude/error_overloaded.json", status: 529),
            .fixture("claude/error_overloaded.json", status: 429, headers: ["retry-after": "3"]),
            .fixture("claude/identify_tool_use.json"),
        ])
        let client = ClaudeClient(configuration: .init(apiKey: "sk-test", retry: .instant(delays: delays)), transport: transport)
        let response = try await client.identify(image: Self.jpeg, hints: .none, profile: .default)
        #expect(response.components.count == 3)
        #expect(delays.values == [1, 3])
    }

    @Test func dropsFallbackBetaWhenRejected() async throws {
        let transport = MockTransport([.fixture("claude/error_fallback_beta.json", status: 400), .fixture("claude/identify_tool_use.json")])
        _ = try await client(transport).identify(image: Self.jpeg, hints: .none, profile: .default)
        let retry = try #require(transport.requests.last)
        #expect(retry.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(retry.jsonBody?["fallbacks"] == nil)
    }

    @Test func surfacesHTTPErrors() async throws {
        let transport = MockTransport([.fixture("claude/error_invalid_key.json", status: 401)])
        await #expect(throws: GreenCoreError.http(status: 401, body: "authentication_error: invalid x-api-key")) {
            _ = try await client(transport).identify(image: Self.jpeg, hints: .none, profile: .default)
        }
    }

    @Test func missingKeyThrowsWithoutNetwork() async throws {
        let transport = MockTransport([])
        let client = ClaudeClient(apiKey: "  ", transport: transport)
        await #expect(throws: GreenCoreError.missingAPIKey("ANTHROPIC_API_KEY")) {
            _ = try await client.identify(image: Self.jpeg, hints: .none, profile: .default)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func timesOut() async throws {
        let client = ClaudeClient(configuration: .init(apiKey: "sk-test", identifyTimeout: 0.05, retry: .none),
                                  transport: SlowTransport())
        await #expect(throws: GreenCoreError.timeout) {
            _ = try await client.identify(image: Self.jpeg, hints: .none, profile: .default)
        }
    }

    @Test func labelsPNGInput() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        #expect(ImageBlock.mediaType(of: png) == "image/png")
        #expect(ImageBlock.mediaType(of: Self.jpeg) == "image/jpeg")
    }
}

/// Never answers within the test's deadline.
struct SlowTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .seconds(10))
        throw URLError(.timedOut)
    }
}
