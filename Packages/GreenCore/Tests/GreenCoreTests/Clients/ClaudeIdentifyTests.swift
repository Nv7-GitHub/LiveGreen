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
        // Sampling parameters and thinking budgets are rejected by these models; Sonnet turns thinking off
        // with `between_tools` for latency.
        #expect(body["temperature"] == nil)
        #expect(body["thinking"]?["type"]?.string == "between_tools")
        #expect(body["tools"]?.array?.first?["name"]?.string == "report_components")
        let estimates = body["tools"]?.array?.first?["input_schema"]?["properties"]?["components"]?["items"]?["properties"]?["fallback_estimates"]
        #expect(estimates?["items"]?["properties"]?["metric"]?["enum"] == ["carbon"], "slim identify schema")

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

    @Test func opusKeepsAdaptiveThinking() async throws {
        let transport = MockTransport([.fixture("claude/identify_tool_use.json")])
        _ = try await client(transport, model: .opus).identify(image: Self.jpeg, hints: .none, profile: .default)
        #expect(try #require(transport.requests.first?.jsonBody)["thinking"] == nil)
    }

    @Test func sendsWorkspaceHeaderWhenSet() async throws {
        let transport = MockTransport([.fixture("claude/identify_tool_use.json")])
        let client = ClaudeClient(configuration: .init(apiKey: "sk-test", workspaceID: "wrkspc_1", retry: .instant()),
                                  transport: transport)
        _ = try await client.identify(image: Self.jpeg, hints: .none, profile: .default)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "anthropic-workspace-id") == "wrkspc_1")
    }

    @Test func streamsToolInputAndReportsItemNames() async throws {
        let input = #"{"scene_title":"Desk setup","components":[{"name":"Dell 27-inch monitor","category":"electronic","bounding_box":{"x":0.1,"y":0.1,"width":0.4,"height":0.5},"fallback_estimates":[{"metric":"carbon","value":300,"low":200,"high":450}]}]}"#
        let cut = input.index(input.startIndex, offsetBy: 70)
        let fragments = [String(input[..<cut]), String(input[cut...])]
        func line(_ value: JSONValue) -> String {
            "data: " + String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
        }
        var lines = [
            line(["type": "message_start", "message": ["id": "msg_1"]]),
            line(["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": ""]]),
            line(["type": "content_block_start", "index": 1,
                  "content_block": ["type": "tool_use", "id": "toolu_1", "name": "report_components", "input": [:]]]),
        ]
        lines += fragments.map { line(["type": "content_block_delta", "index": 1,
                                       "delta": ["type": "input_json_delta", "partial_json": .string($0)]]) }
        lines += [line(["type": "message_delta", "delta": ["stop_reason": "tool_use"]]), line(["type": "message_stop"])]
        let transport = StreamingMockTransport(lines: lines)
        let updates = Recorder<IdentifyProgress>()
        let response = try await ClaudeClient(configuration: .init(apiKey: "sk-test", retry: .instant()), transport: transport)
            .identify(image: Self.jpeg, hints: .none, profile: .default) { updates.append($0) }

        #expect(response.components.first?.name == "Dell 27-inch monitor")
        #expect(response.components.first?.estimates[.carbon]?.value == 300)
        #expect(updates.values.contains { $0.itemNames == ["Dell 27-inch monitor"] })
        let body = try #require(transport.request?.jsonBody)
        #expect(body["stream"] == true)
        #expect(body["tools"]?.array?.first?["eager_input_streaming"] == true)
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

    @Test func brandsComeFromLogosOrDesignAndModelNumbersOnlyFromPrint() {
        let system = ClaudeClient.identifySystemPrompt(vocabulary: .default, carbonEstimateOnly: true)
        // Makers are recognized by design too (a Mac keyboard), with a stated confidence, not left out.
        #expect(system.contains("Recognize makers by design as well as by printed names"))
        #expect(system.contains("⌘ command and option keys"))
        #expect(system.contains("model_line"))
        #expect(system.contains("confidence"))
        #expect(!system.contains("never infer it from shape"))
        // An exact model number still has to be printed.
        #expect(system.contains("Never compose one from the model line"))

        let item = ReportComponentsTool.carbonEstimateOnlySchema["properties"]?["components"]?["items"]?["properties"]
        let identifiers = item?["identifiers"]
        let fields = identifiers?["properties"]
        #expect(fields?["confidence"]?["enum"] == ["high", "medium", "low", nil])
        #expect(fields?["model"]?["description"]?.string?.contains("Never guess one") == true)
        let required = identifiers?["required"]?.array?.compactMap(\.string) ?? []
        #expect(Set(required).isSuperset(of: ["brand", "model", "model_line", "confidence", "appearance_cues"]))
        // No example product names in descriptions: the fast models copy them into answers.
        let descriptions = ([item?["name"]] + ["brand", "model", "model_line", "appearance_cues"].map { fields?[$0] })
            .compactMap { $0?["description"]?.string }
        #expect(descriptions.count == 5)
        for word in ["Dell", "Apple", "MacBook", "ASUS", "Zenbook"] {
            #expect(!descriptions.contains { $0.contains(word) }, "\(word) in a schema description")
        }
        // The cues sort before the brand they support (the request encodes keys sorted).
        #expect(fields?.object?.keys.sorted().first == "appearance_cues")
        // Alternatives keep the plain identifiers.
        #expect(SchemaParts.identifiers["properties"]?["model_line"] == nil)
    }

    @Test func parsesBrandModelLineAndConfidence() throws {
        let input: JSONValue = ["scene_title": "Desk", "components": [[
            "name": "Apple MacBook Pro 14-inch", "category": "electronic",
            "bounding_box": ["x": 0.1, "y": 0.2, "width": 0.5, "height": 0.4],
            "identifiers": ["appearance_cues": "⌘ command keys, notch, black keyboard well", "brand": "Apple",
                            "model": .null, "model_line": "Apple MacBook Pro 14-inch (M-series)", "confidence": " Medium",
                            "gtin": .null, "materials": []],
        ], [
            "name": "Mug", "category": "household", "bounding_box": ["x": 0, "y": 0, "width": 0.1, "height": 0.1],
            "identifiers": ["brand": .null, "model": .null, "model_line": .null, "confidence": "certain", "gtin": .null, "materials": []],
        ]]]
        let response = try ReportComponentsTool.parse(input)
        let laptop = response.components[0].identifiers
        #expect(laptop.brand == "Apple")
        #expect(laptop.model == nil)
        #expect(laptop.modelLine == "MacBook Pro 14-inch (M-series)", "the repeated brand is dropped from the line")
        #expect(laptop.confidence == .medium)
        #expect(laptop.appearanceCues == "⌘ command keys, notch, black keyboard well")
        let size = Quantities(screenSizeInches: 14.2)
        #expect(laptop.lineKey(category: .electronic, quantities: size) == "bl:electronic|apple|macbook pro 14-inch (m-series)|14in")
        #expect(laptop.resolutionKey(category: .electronic, quantities: size) == laptop.lineKey(category: .electronic, quantities: size))

        let mug = response.components[1].identifiers
        #expect(mug.modelLine == nil && mug.confidence == nil, "unknown confidence values are ignored")
        #expect(mug.lineKey(category: .household, quantities: Quantities(massKg: 0.3)) == nil)
    }

    @Test func aLineThatOnlyRepeatsTheBrandIsDropped() throws {
        let input: JSONValue = ["components": [[
            "name": "Coca-Cola can", "category": "food", "bounding_box": ["x": 0, "y": 0, "width": 0.1, "height": 0.1],
            "identifiers": ["brand": "Coca-Cola", "model": .null, "model_line": "coca-cola", "confidence": "high",
                            "gtin": .null, "materials": []],
        ]]]
        let ids = try ReportComponentsTool.parse(input).components[0].identifiers
        #expect(ids.brand == "Coca-Cola")
        #expect(ids.modelLine == nil)
        #expect(Identifiers.modelLine("Dell XPS 13", brand: "Dell") == "XPS 13")
        #expect(Identifiers.modelLine("Dellwood desk", brand: "Dell") == "Dellwood desk")
    }

    @Test func lowConfidenceLinesAreNotLookedUpOrCached() {
        let size = Quantities(screenSizeInches: 13.6)
        var ids = Identifiers(brand: "Apple", modelLine: "MacBook Air", confidence: .low)
        #expect(ids.confidentModelLine == nil)
        #expect(ids.lineKey(category: .electronic, quantities: size) == nil)
        // Grok can return a null confidence, and Claude's tool input is not strictly validated: no stated
        // confidence is not a confident line.
        ids.confidence = nil
        #expect(ids.confidentModelLine == nil)
        #expect(ids.lineKey(category: .electronic, quantities: size) == nil)
        ids.confidence = .medium
        #expect(ids.confidentModelLine == "MacBook Air")
        ids.confidence = .high
        #expect(ids.lineKey(category: .electronic, quantities: size) == "bl:electronic|apple|macbook air|14in")
        ids.model = "A2681"
        #expect(ids.lineKey(category: .electronic, quantities: size) == nil, "a model number keys the cache instead")
        #expect(ids.resolutionKey(category: .electronic, quantities: size) == "bm:apple|a2681")
    }

    @Test func hintTextSkipsKeyLegendsAndRepeats() {
        let keys = ["esc", "Q", "W", "E", "command", "option", "command", "option", "⌘"]
        let lines = ClaudeClient.hintTextLines(keys + (1...50).map { "Line \($0)" })
        #expect(lines.prefix(4) == ["esc", "command", "option", "Line 1"])
        #expect(lines.count == 40)
        let text = ClaudeClient.identifyUserText(hints: OCRHints(textLines: ["Q", "MacBook Pro", "W"]), profile: .default)
        #expect(text.contains("  MacBook Pro"))
        #expect(!text.contains("  Q"))
    }

    @Test func photosAreSentAtTheModelsHighResolutionLimit() {
        // A 12 MP iPhone photo keeps far more detail than the old 1568 px cap, within the ~3.75 MP API limit.
        let photo = IdentifyImage.fittedSize(width: 4032, height: 3024)
        #expect(photo.width >= 2200 && photo.width > 1568)
        #expect(photo.width * photo.height <= 3_750_000)
        #expect(abs(photo.width / photo.height - 4.0 / 3.0) < 0.01)
        // A panorama is capped by the long edge; a small image is never upscaled.
        #expect(IdentifyImage.fittedSize(width: 8000, height: 1000).width == 2576)
        let small = IdentifyImage.fittedSize(width: 1200, height: 900)
        #expect(small.width == 1200 && small.height == 900)
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
