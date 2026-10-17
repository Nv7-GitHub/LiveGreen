import Foundation

/// Retries transient HTTP failures (429, 408, 5xx, 529 overloaded) with exponential backoff,
/// honoring `Retry-After` when the server sends it.
public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Double
    public var maxDelay: Double
    /// Injected so tests do not actually wait.
    public var sleep: @Sendable (Double) async throws -> Void

    public init(maxAttempts: Int = 3, baseDelay: Double = 1, maxDelay: Double = 8,
                sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.sleep = sleep
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1)

    static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504, 529]

    func delay(forAttempt attempt: Int, response: HTTPURLResponse) -> Double {
        if let retryAfter = response.retryAfterSeconds { return min(retryAfter, maxDelay) }
        return min(baseDelay * pow(2, Double(attempt - 1)), maxDelay)
    }

    /// Sends `request`, retrying retryable statuses. Returns the final response whatever its status.
    func send(_ request: URLRequest, via transport: any HTTPTransport) async throws -> (Data, HTTPURLResponse) {
        var attempt = 1
        while true {
            let (data, response) = try await transport.send(request)
            guard Self.retryableStatuses.contains(response.statusCode), attempt < maxAttempts else {
                return (data, response)
            }
            try await sleep(delay(forAttempt: attempt, response: response))
            attempt += 1
        }
    }
}
