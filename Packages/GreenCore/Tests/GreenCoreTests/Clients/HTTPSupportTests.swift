import Foundation
import Testing
@testable import GreenCore

@Suite("HTTP support")
struct HTTPSupportTests {
    @Test func jsonValueRoundTripsTypes() throws {
        let data = Data(#"{"flag":true,"count":1,"zero":0,"ratio":0.5,"name":"x","none":null,"list":[1,"2"]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(value["flag"] == .bool(true))
        #expect(value["count"] == .number(1), "integers stay numbers, not booleans")
        #expect(value["zero"] == .number(0))
        #expect(value["ratio"]?.double == 0.5)
        #expect(value["none"]?.isNull == true)
        #expect(value["list"]?.array?[1].double == 2, "numeric strings read as numbers")
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(again == value)
    }

    @Test func retryStopsOnSuccessOrNonRetryable() async throws {
        let delays = Recorder<Double>()
        let transport = MockTransport([.json("", status: 503), .json("{}", status: 200)])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let (_, response) = try await RetryPolicy.instant(delays: delays).send(request, via: transport)
        #expect(response.statusCode == 200)
        #expect(delays.values == [1])

        let badRequest = MockTransport([.json("", status: 400)])
        let (_, bad) = try await RetryPolicy.instant().send(request, via: badRequest)
        #expect(bad.statusCode == 400)
        #expect(badRequest.requests.count == 1)
    }

    @Test func retryAfterIsCapped() {
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil,
                                       headerFields: ["Retry-After": "120"])!
        #expect(RetryPolicy(maxDelay: 8).delay(forAttempt: 1, response: response) == 8)
    }

    @Test func deadlinePassesFastWork() async throws {
        let value = try await withDeadline(seconds: 5) { 42 }
        #expect(value == 42)
    }
}
