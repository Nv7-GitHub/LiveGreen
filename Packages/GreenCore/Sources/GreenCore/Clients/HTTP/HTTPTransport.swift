import Foundation

/// The one seam every network client goes through, so tests can replay recorded fixtures.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production transport backed by `URLSession` async/await.
public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GreenCoreError.decoding("Non-HTTP response from \(request.url?.absoluteString ?? "?")")
            }
            return (data, http)
        } catch let error as URLError where error.code == .timedOut {
            throw GreenCoreError.timeout
        }
    }
}

extension HTTPURLResponse {
    var isSuccess: Bool { (200..<300).contains(statusCode) }

    /// `Retry-After` in seconds (delta-seconds form only; HTTP-date is ignored).
    var retryAfterSeconds: Double? {
        value(forHTTPHeaderField: "retry-after").flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }
}

extension Data {
    /// Response body as text for error messages, truncated to keep logs readable.
    var bodyPreview: String {
        let text = String(decoding: prefix(2_000), as: UTF8.self)
        return count > 2_000 ? text + "…" : text
    }
}
