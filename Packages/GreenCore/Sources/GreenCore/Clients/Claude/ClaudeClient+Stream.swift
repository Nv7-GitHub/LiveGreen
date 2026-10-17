import Foundation

extension ClaudeClient {
    /// One streamed tool call: the tool input arrives as `input_json_delta` fragments (the tool is sent with
    /// `eager_input_streaming`, so fragments are not buffered server-side) and the partial JSON is reported
    /// through `progress` as it grows. Anything other than a clean, parseable call (an HTTP error, a refusal,
    /// a text answer, cut-off or invalid input) falls back to the non-streaming `runTool` loop, which retries,
    /// nudges and returns decode errors to Claude.
    func streamTool<T: Sendable>(_ spec: ToolCallSpec, userContent: [JSONValue],
                                 progress: @escaping @Sendable (String) -> Void,
                                 parse: @escaping @Sendable (_ input: JSONValue, _ transcript: [JSONValue]) throws -> T)
        async throws -> T {
        guard let streaming = transport as? any HTTPStreamingTransport else {
            return try await runTool(spec, userContent: userContent, parse: parse)
        }
        guard let apiKey = configuration.apiKey?.trimmedNonEmpty else {
            throw GreenCoreError.missingAPIKey("ANTHROPIC_API_KEY")
        }
        let started = Date()
        let streamed: StreamedToolCall?
        do {
            streamed = try await withDeadline(seconds: spec.timeout) {
                try await streamOnce(spec, userContent: userContent, apiKey: apiKey, via: streaming, progress: progress)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch GreenCoreError.timeout {
            throw GreenCoreError.timeout
        } catch GreenCoreError.invalidModelOutput(let message) {
            throw GreenCoreError.invalidModelOutput(message)
        } catch {
            streamed = nil
        }
        if let streamed, let input = streamed.input, let value = try? parse(input, []) {
            return value
        }
        var fallback = spec
        fallback.timeout = max(spec.timeout - Date().timeIntervalSince(started), 10)
        return try await runTool(fallback, userContent: userContent, parse: parse)
    }

    struct StreamedToolCall: Sendable {
        /// The parsed tool input, nil when the call never happened or its JSON did not parse.
        var input: JSONValue?
        var stopReason: String?
    }

    private func streamOnce(_ spec: ToolCallSpec, userContent: [JSONValue], apiKey: String,
                            via transport: any HTTPStreamingTransport,
                            progress: @Sendable (String) -> Void) async throws -> StreamedToolCall {
        var body = request(spec, messages: [.init(role: "user", content: userContent)], maxTokens: spec.maxTokens)
        body.stream = true
        body.tools = body.tools.map { tool in
            guard tool["name"]?.string == spec.toolName, case .object(var fields) = tool else { return tool }
            fields["eager_input_streaming"] = true
            return .object(fields)
        }
        let (lines, response) = try await transport.lines(for: try urlRequest(for: body, apiKey: apiKey, timeout: spec.timeout))
        guard response.isSuccess else {
            var text = ""
            for try await line in lines { text += line + "\n"; if text.count > 2_000 { break } }
            throw GreenCoreError.http(status: response.statusCode, body: text)
        }

        var toolIndex: Int?
        var json = ""
        var stopReason: String?
        var category: String?
        for try await line in lines {
            guard line.hasPrefix("data:"), let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                  let event = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
            switch event["type"]?.string {
            case "content_block_start":
                let block = event["content_block"]
                if toolIndex == nil, block?["type"]?.string == "tool_use", block?["name"]?.string == spec.toolName {
                    toolIndex = event["index"]?.double.map(Int.init)
                }
            case "content_block_delta":
                guard let toolIndex, event["index"]?.double.map(Int.init) == toolIndex,
                      event["delta"]?["type"]?.string == "input_json_delta" else { continue }
                json += event["delta"]?["partial_json"]?.string ?? ""
                progress(json)
            case "message_delta":
                stopReason = event["delta"]?["stop_reason"]?.string ?? stopReason
                category = event["delta"]?["stop_details"]?["category"]?.string ?? category
            case "error":
                let type = event["error"]?["type"]?.string ?? "error"
                throw GreenCoreError.http(status: type == "overloaded_error" ? 529 : 500,
                                          body: "\(type): \(event["error"]?["message"]?.string ?? "stream error")")
            default:
                break
            }
        }
        if stopReason == "refusal" {
            throw GreenCoreError.invalidModelOutput("Claude declined the request (\(category ?? "unspecified")).")
        }
        let input = json.data(using: .utf8).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        return StreamedToolCall(input: stopReason == "max_tokens" ? nil : input, stopReason: stopReason)
    }
}
