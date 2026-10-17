import Foundation

extension ClaudeClient {
    /// Sends one Messages request with retries for 429 / 5xx / 529 overloaded (honoring `retry-after`).
    func send(_ body: MessagesRequest, timeout: Double) async throws -> MessagesResponse {
        guard let apiKey = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw GreenCoreError.missingAPIKey("ANTHROPIC_API_KEY")
        }
        let (data, response) = try await configuration.retry.send(
            try urlRequest(for: body, apiKey: apiKey, timeout: timeout), via: transport)

        if response.statusCode == 400, body.fallbacks != nil, Self.rejectsFallbackBeta(data) {
            var plain = body
            plain.fallbacks = nil
            return try await send(plain, timeout: timeout)
        }
        guard response.isSuccess else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))
                .map { "\($0.error.type): \($0.error.message)" } ?? data.bodyPreview
            throw GreenCoreError.http(status: response.statusCode, body: message)
        }
        do {
            return try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw GreenCoreError.decoding("Claude response: \(error)")
        }
    }

    func urlRequest(for body: MessagesRequest, apiKey: String, timeout: Double) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if let workspaceID = configuration.workspaceID?.trimmedNonEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }
        if body.fallbacks != nil {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        return request
    }

    /// True for the 400 an account returns when the fallback beta or parameter is not enabled.
    static func rejectsFallbackBeta(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) else { return false }
        let message = envelope.error.message.lowercased()
        return message.contains("fallback") || message.contains("anthropic-beta")
    }
}
