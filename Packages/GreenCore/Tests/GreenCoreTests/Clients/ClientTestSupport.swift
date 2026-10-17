import Foundation
import Synchronization
@testable import GreenCore

/// Replays canned responses in order and records every request it was sent.
final class MockTransport: HTTPTransport {
    struct Reply: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String]

        init(status: Int = 200, body: Data, headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }

        static func fixture(_ path: String, status: Int = 200, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, body: Fixture.data(path), headers: headers)
        }

        static func json(_ text: String, status: Int = 200) -> Reply {
            Reply(status: status, body: Data(text.utf8))
        }
    }

    private let state: Mutex<(replies: [Reply], requests: [URLRequest])>
    private let route: (@Sendable (URLRequest) -> Reply?)?

    /// Replies are consumed in order.
    init(_ replies: [Reply]) {
        state = Mutex((replies, []))
        route = nil
    }

    /// Replies chosen per request (for concurrent clients such as ENERGY STAR).
    init(route: @escaping @Sendable (URLRequest) -> Reply?) {
        state = Mutex(([], []))
        self.route = route
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = state.withLock { state in
            state.requests.append(request)
            if let route { return route(request) }
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        guard let reply else { throw URLError(.resourceUnavailable) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        return (reply.body, response)
    }
}

enum Fixture {
    /// Loads `Fixtures/<path>` from the test bundle, e.g. "claude/identify_tool_use.json".
    static func data(_ path: String) -> Data {
        let url = Bundle.module.resourceURL!.appending(path: "Fixtures").appending(path: path)
        guard let data = try? Data(contentsOf: url) else { fatalError("Missing fixture \(path)") }
        return data
    }
}

extension URLRequest {
    /// The JSON body decoded as `JSONValue`.
    var jsonBody: JSONValue? {
        httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
    }

    func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == name }?.value
    }
}

/// Thread-safe append-only log.
final class Recorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])
    func append(_ value: Value) { storage.withLock { $0.append(value) } }
    var values: [Value] { storage.withLock { $0 } }
}

extension RetryPolicy {
    /// Retries without waiting, recording each requested delay.
    static func instant(maxAttempts: Int = 3, delays: Recorder<Double>? = nil) -> RetryPolicy {
        RetryPolicy(maxAttempts: maxAttempts, sleep: { delay in delays?.append(delay) })
    }
}
