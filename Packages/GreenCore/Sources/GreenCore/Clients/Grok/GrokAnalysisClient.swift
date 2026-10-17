import Foundation

/// xAI Grok as the analysis provider: identify, alternatives and spec research (spec §5.3, §5.4 T2, §7)
/// over the Responses API (`POST /v1/responses`). It reuses the Claude prompts and tool schemas, sent as a
/// strict `json_schema` output format instead of a tool, and research adds the server-side `web_search`
/// tool, whose search results and URL citations become the set of pages a value may cite.
public struct GrokAnalysisClient: Sendable {
    public struct Configuration: Sendable {
        /// `XAI_API_KEY`. Calls throw `GreenCoreError.missingAPIKey` while it is nil or empty.
        public var apiKey: String?
        /// Alternatives and spec research. `grok-4.3` reasons before answering, which suits cited research;
        /// `grok-4.7` did not finish an identify call within 4 minutes in testing.
        public var model: String
        /// Identify. The non-reasoning model answers a desk photo in ~9 s with the slim schema versus ~14–25 s
        /// for `grok-4.3`, with the same box accuracy; it copied example model numbers only while the schema
        /// contained one.
        public var identifyModel: String
        public var baseURL: URL
        public var identifyTimeout: Double
        public var alternativesTimeout: Double
        public var researchTimeout: Double
        public var vocabulary: ReferenceVocabulary
        public var retry: RetryPolicy

        public init(apiKey: String?, model: String = "grok-4.3", identifyModel: String = "grok-4.20-0309-non-reasoning",
                    baseURL: URL = URL(string: "https://api.x.ai")!,
                    identifyTimeout: Double = 45, alternativesTimeout: Double = 90, researchTimeout: Double = 60,
                    vocabulary: ReferenceVocabulary = .default, retry: RetryPolicy = .default) {
            self.apiKey = apiKey
            self.model = model
            self.identifyModel = identifyModel
            self.baseURL = baseURL
            self.identifyTimeout = identifyTimeout
            self.alternativesTimeout = alternativesTimeout
            self.researchTimeout = researchTimeout
            self.vocabulary = vocabulary
            self.retry = retry
        }
    }

    public var configuration: Configuration
    let transport: any HTTPTransport

    public init(configuration: Configuration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Model output that failed to decode is sent back once with the problem, then the call fails.
    static let maxAttempts = 2

    /// One structured-output exchange: the JSON object Grok returned plus every URL its web searches surfaced.
    struct StructuredReply: Sendable {
        var output: JSONValue
        var sourceURLs: [URL]
    }

    /// Sends `content` with `instructions` and decodes the reply with `parse`, retrying once with the decode
    /// error when the output does not fit.
    /// With `progress`, the reply is streamed and the partial output text is reported as it arrives.
    func respond<T: Sendable>(model: String? = nil, instructions: String, content: [JSONValue], schemaName: String,
                              schema: JSONValue, tools: [JSONValue] = [], timeout: Double,
                              progress: (@Sendable (String) -> Void)? = nil,
                              parse: @escaping @Sendable (StructuredReply) throws -> T) async throws -> T {
        let model = model ?? configuration.model
        let streaming = progress == nil ? nil : transport as? any HTTPStreamingTransport
        return try await withDeadline(seconds: timeout) {
            var input: [JSONValue] = [["role": "user", "content": .array(content)]]
            var lastProblem = ""
            for _ in 0..<Self.maxAttempts {
                let request = try makeRequest(model: model, instructions: instructions, input: input, schemaName: schemaName,
                                              schema: schema, tools: tools, timeout: timeout, stream: streaming != nil)
                let reply: StructuredReply
                if let progress, let streaming {
                    reply = try await stream(request, via: streaming, progress: progress)
                } else {
                    reply = try await send(request)
                }
                do {
                    return try parse(reply)
                } catch {
                    lastProblem = "\(error)"
                    input.append(["role": "user", "content": .string(
                        "Your JSON did not fit: \(lastProblem). Reply again with corrected JSON matching the schema.")])
                }
            }
            throw GreenCoreError.invalidModelOutput("Grok \(schemaName): \(lastProblem)")
        }
    }

    func makeRequest(model: String, instructions: String, input: [JSONValue], schemaName: String, schema: JSONValue,
                     tools: [JSONValue], timeout: Double, stream: Bool) throws -> URLRequest {
        guard let apiKey = configuration.apiKey?.trimmedNonEmpty else { throw GreenCoreError.missingAPIKey("XAI_API_KEY") }
        var body: [String: JSONValue] = [
            "model": .string(model),
            // Requests with images can fail when the server stores them.
            "store": false,
            "instructions": .string(instructions + "\n\n" + Self.structuredOutputNote),
            "input": .array(input),
            "text": ["format": ["type": "json_schema", "name": .string(schemaName), "strict": true, "schema": schema]],
        ]
        if !tools.isEmpty { body["tools"] = .array(tools) }
        if stream { body["stream"] = true }

        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/responses"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(JSONValue.object(body))
        return request
    }

    func send(_ request: URLRequest) async throws -> StructuredReply {
        let (data, response) = try await configuration.retry.send(request, via: transport)
        guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }
        let reply: JSONValue
        do {
            reply = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw GreenCoreError.decoding("Grok response: \(error)")
        }
        return try Self.structuredReply(from: reply)
    }

    /// Reads a server-sent-event stream: `response.output_text.delta` events build the output text (reported
    /// through `progress`), and `response.completed` carries the full response.
    func stream(_ request: URLRequest, via transport: any HTTPStreamingTransport,
                progress: @Sendable (String) -> Void) async throws -> StructuredReply {
        let (lines, response) = try await transport.lines(for: request)
        guard response.isSuccess else {
            var body = ""
            for try await line in lines { body += line + "\n"; if body.count > 2_000 { break } }
            throw GreenCoreError.http(status: response.statusCode, body: body)
        }
        var text = ""
        for try await line in lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
            switch event["type"]?.string {
            case "response.output_text.delta":
                text += event["delta"]?.string ?? ""
                progress(text)
            case "response.completed":
                if let full = event["response"] { return try Self.structuredReply(from: full) }
            case "response.failed", "response.incomplete", "error":
                let message = event["response"]?["error"]?["message"]?.string ?? event["message"]?.string
                    ?? event["response"]?["incomplete_details"]?["reason"]?.string ?? "stream ended early"
                throw GreenCoreError.invalidModelOutput("Grok stream: \(message)")
            default:
                break
            }
        }
        // No completed event: use what was streamed.
        guard let data = text.data(using: .utf8), let output = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw GreenCoreError.invalidModelOutput("Grok stream ended without a complete answer.")
        }
        return StructuredReply(output: output, sourceURLs: [])
    }

    /// Pulls the output text (parsed as JSON) and the web-search source and citation URLs out of a response.
    static func structuredReply(from response: JSONValue) throws -> StructuredReply {
        if let status = response["status"]?.string, status != "completed" {
            let reason = response["incomplete_details"]?["reason"]?.string ?? response["error"]?["message"]?.string ?? status
            throw GreenCoreError.invalidModelOutput("Grok response \(status): \(reason)")
        }
        var text: String?
        var urls: [URL] = []
        for item in response["output"]?.array ?? [] {
            switch item["type"]?.string {
            case "web_search_call":
                urls += (item["action"]?["sources"]?.array ?? []).compactMap { $0["url"]?.string.flatMap(URL.init(string:)) }
            case "message":
                for part in item["content"]?.array ?? [] {
                    if part["type"]?.string == "refusal" {
                        throw GreenCoreError.invalidModelOutput("Grok declined the request: \(part["refusal"]?.string ?? "")")
                    }
                    if part["type"]?.string == "output_text", let value = part["text"]?.string { text = value }
                    urls += (part["annotations"]?.array ?? []).compactMap { $0["url"]?.string.flatMap(URL.init(string:)) }
                }
            default:
                break
            }
        }
        guard let text, let data = text.data(using: .utf8) else {
            throw GreenCoreError.invalidModelOutput("Grok returned no output text.")
        }
        do {
            return StructuredReply(output: try JSONDecoder().decode(JSONValue.self, from: data), sourceURLs: urls)
        } catch {
            throw GreenCoreError.invalidModelOutput("Grok output is not JSON: \(error)")
        }
    }

    /// The shared prompts are written for Claude's tools; this maps "call the tool" to the JSON reply.
    static let structuredOutputNote = """
        Response format: there are no client tools in this conversation. Wherever these instructions say to \
        call a tool such as `report_components`, `suggest_alternatives` or `report_specs`, reply instead with a \
        single JSON object that matches the response schema of that name. Use web_search when it is available.
        """
}
