import Foundation
import Testing
@testable import GreenCore

@Suite("ElectricityMapsClient")
struct ElectricityMapsClientTests {
    static let now = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17T00:00:00Z

    func client(_ transport: MockTransport, key: String? = "em-key") -> ElectricityMapsClient {
        ElectricityMapsClient(apiKey: key, retry: .instant(), transport: transport, now: { Self.now })
    }

    @Test func latestByZone() async throws {
        let transport = MockTransport([.fixture("electricitymaps/latest.json")])
        let point = try await client(transport).latest(zone: "US-NE-ISNE")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.electricitymap.org/v3/carbon-intensity/latest?zone=US-NE-ISNE")
        #expect(request.value(forHTTPHeaderField: "auth-token") == "em-key")
        #expect(point.gramsCO2ePerKWh == 243)
        #expect(point.zone == "US-NE-ISNE")
        #expect(point.isEstimated)
        #expect(point.date == Date(timeIntervalSince1970: 1_792_184_400))
    }

    @Test func latestByCoordinate() async throws {
        let transport = MockTransport([.fixture("electricitymaps/latest.json")])
        _ = try await client(transport).latest(at: .coordinate(latitude: 42.37, longitude: -71.12))
        let request = try #require(transport.requests.first)
        #expect(request.queryValue("lat") == "42.37")
        #expect(request.queryValue("lon") == "-71.12")
        #expect(request.queryValue("zone") == nil)
    }

    @Test func historySortsAndSkipsGaps() async throws {
        let transport = MockTransport([.fixture("electricitymaps/history.json")])
        let points = try await client(transport).history(zone: "US-NE-ISNE", hours: 24)
        #expect(transport.requests.first?.url?.path() == "/v3/carbon-intensity/history")
        #expect(points.map(\.gramsCO2ePerKWh) == [238, 251, 243], "oldest first, null reading dropped")
    }

    @Test func longHistoryStaysOnTheFreeEndpoint() async throws {
        let transport = MockTransport([.fixture("electricitymaps/history.json")])
        let points = try await client(transport).history(zone: "US-NE-ISNE", hours: 168)
        #expect(transport.requests.map { $0.url?.path() } == ["/v3/carbon-intensity/history"])
        #expect(points.count == 3)
    }

    @Test func pastRangeFallsBackToHistoryWhenThePlanRefusesIt() async throws {
        let transport = MockTransport([.json("{\"error\":\"Not available on your plan\"}", status: 403),
                                       .fixture("electricitymaps/history.json")])
        var client = client(transport)
        client.usesPastRange = true
        let points = try await client.history(zone: "US-NE-ISNE", hours: 168)
        #expect(transport.requests.map { $0.url?.path() } == ["/v3/carbon-intensity/past-range", "/v3/carbon-intensity/history"])
        #expect(points.count == 3)
    }

    @Test func commercialKeyUsesPastRange() async throws {
        let transport = MockTransport([.fixture("electricitymaps/past_range.json")])
        var client = client(transport)
        client.usesPastRange = true
        let points = try await client.history(zone: "DE", hours: 168)
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/v3/carbon-intensity/past-range")
        #expect(request.queryValue("start") == "2026-10-10T00:00:00Z")
        #expect(request.queryValue("end") == "2026-10-17T00:00:00Z")
        #expect(points.count == 3)
        #expect(points[1].date == Date(timeIntervalSince1970: 1_791_594_000), "timestamps without fractional seconds parse")
    }

    @Test func missingKeyThrows() async throws {
        await #expect(throws: GreenCoreError.missingAPIKey("ELECTRICITYMAPS_API_KEY")) {
            _ = try await client(MockTransport([]), key: nil).latest(zone: "DE")
        }
    }

    @Test func unauthorizedThrowsHTTP() async throws {
        let transport = MockTransport([.json("{\"error\":\"Invalid auth-token\"}", status: 401)])
        await #expect(throws: GreenCoreError.http(status: 401, body: "{\"error\":\"Invalid auth-token\"}")) {
            _ = try await client(transport).latest(zone: "DE")
        }
    }
}

@Suite("GrokImageClient")
struct GrokImageClientTests {
    static let photo = Data([0xFF, 0xD8, 0xFF, 0xDB, 0x01])

    func client(_ transport: MockTransport) -> GrokImageClient {
        GrokImageClient(configuration: .init(apiKey: "xai-key", retry: .instant()), transport: transport)
    }

    @Test func buildsEditRequestAndDecodesBase64() async throws {
        let transport = MockTransport([.fixture("grok/edit_b64.json")])
        let image = try await client(transport).editImage(Self.photo, prompt: "Replace the cup")

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.x.ai/v1/images/edits")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xai-key")
        #expect(request.timeoutInterval == 60)
        let body = try #require(request.jsonBody)
        #expect(body["model"]?.string == "grok-imagine-image-2.0")
        #expect(body["prompt"]?.string == "Replace the cup")
        #expect(body["image"]?["type"]?.string == "image_url")
        #expect(body["image"]?["url"]?.string == "data:image/jpeg;base64,\(Self.photo.base64EncodedString())")
        #expect(image.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test func downloadsURLResponse() async throws {
        let edited = Data([0xFF, 0xD8, 0xFF, 0xE1])
        let transport = MockTransport([.fixture("grok/edit_url.json"), MockTransport.Reply(body: edited)])
        let image = try await client(transport).editImage(Self.photo, prompt: "p")
        #expect(image == edited)
        #expect(transport.requests.last?.url?.absoluteString == "https://imgen.x.ai/xai-imgen/xai-tmp-imgen-1a2b3c.jpeg")
    }

    @Test func errorsSurface() async throws {
        let transport = MockTransport([.json("{\"error\":\"bad\"}", status: 400)])
        await #expect(throws: GreenCoreError.http(status: 400, body: "{\"error\":\"bad\"}")) {
            _ = try await client(transport).editImage(Self.photo, prompt: "p")
        }
        await #expect(throws: GreenCoreError.missingAPIKey("XAI_API_KEY")) {
            _ = try await GrokImageClient(apiKey: nil, transport: MockTransport([])).editImage(Self.photo, prompt: "p")
        }
        let empty = MockTransport([.json("{\"data\":[]}")])
        await #expect(throws: GreenCoreError.invalidModelOutput("Grok returned no image")) {
            _ = try await client(empty).editImage(Self.photo, prompt: "p")
        }
    }

    @Test func promptFromSelectedSwaps() throws {
        let cupID = UUID(), plugAltID = UUID(), cupAltID = UUID()
        let cup = Component(id: cupID, name: "disposable coffee cup", category: .packaging,
                            boundingBox: NormalizedRect(x: 0.78, y: 0.52, width: 0.12, height: 0.2),
                            alternatives: [Alternative(id: cupAltID, name: "reusable steel cup", category: .packaging, rationale: "")])
        let charger = Component(name: "e-bike charger", category: .electronic,
                                boundingBox: NormalizedRect(x: 0.05, y: 0.05, width: 0.1, height: 0.1),
                                alternatives: [Alternative(id: plugAltID, kind: .smartPlugScheduling, name: "Smart plug",
                                                           category: .electronic, rationale: "")])
        let lamp = Component(name: "lamp", category: .electronic)
        let result = ScanResult(title: "Desk", components: [cup, charger, lamp],
                                selectedAlternatives: [cupID: cupAltID, charger.id: plugAltID])

        let prompt = try #require(GreenerImagePrompt.make(for: result))
        #expect(prompt.contains("1. Replace the disposable coffee cup (right side of the photo) with: reusable steel cup."))
        #expect(prompt.contains("2. Plug the e-bike charger (upper left of the photo) into a small white smart plug"))
        #expect(prompt.contains("camera angle"))
        #expect(prompt.contains("photorealistic"))
        #expect(!prompt.contains("lamp"))
        #expect(GreenerImagePrompt.make(swaps: []) == nil)
    }
}
