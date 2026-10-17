import Foundation

/// xAI Grok as the analysis provider: identify, alternatives and spec research (spec §5.3, §5.4 T2, §7)
/// over the Responses API (`POST /v1/responses`). It reuses the Claude prompts and tool schemas, sent as a
/// strict `json_schema` output format instead of a tool, and research adds the server-side `web_search`
/// tool, whose search results and URL citations become the set of pages a value may cite.
public struct GrokAnalysisClient: Sendable {
    public struct Configuration: Sendable {
        /// `XAI_API_KEY`. Calls throw `GreenCoreError.missingAPIKey` while it is nil or empty.
        public var apiKey: String?
        /// Defaults to `grok-4.3`: in testing it identified a desk scene in ~25 s without inventing model
        /// numbers, where `grok-4.7` did not finish within 4 minutes and the non-reasoning model copied
        /// example identifiers.
        public var model: String
        public var baseURL: URL
        public var identifyTimeout: Double
        public var alternativesTimeout: Double
        public var researchTimeout: Double
        public var vocabulary: ReferenceVocabulary
        public var retry: RetryPolicy

        public init(apiKey: String?, model: String = "grok-4.3", baseURL: URL = URL(string: "https://api.x.ai")!,
                    identifyTimeout: Double = 90, alternativesTimeout: Double = 90, researchTimeout: Double = 60,
                    vocabulary: ReferenceVocabulary = .default, retry: RetryPolicy = .default) {
            self.apiKey = apiKey
            self.model = model
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
    func respond<T: Sendable>(instructions: String, content: [JSONValue], schemaName: String, schema: JSONValue,
                              tools: [JSONValue] = [], timeout: Double,
                              parse: @escaping @Sendable (StructuredReply) throws -> T) async throws -> T {
        try await withDeadline(seconds: timeout) {
            var input: [JSONValue] = [["role": "user", "content": .array(content)]]
            var lastProblem = ""
            for _ in 0..<Self.maxAttempts {
                let reply = try await send(instructions: instructions, input: input, schemaName: schemaName,
                                           schema: schema, tools: tools, timeout: timeout)
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

    func send(instructions: String, input: [JSONValue], schemaName: String, schema: JSONValue,
              tools: [JSONValue], timeout: Double) async throws -> StructuredReply {
        guard let apiKey = configuration.apiKey?.trimmedNonEmpty else { throw GreenCoreError.missingAPIKey("XAI_API_KEY") }
        var body: [String: JSONValue] = [
            "model": .string(configuration.model),
            // Requests with images can fail when the server stores them.
            "store": false,
            "instructions": .string(instructions + "\n\n" + Self.structuredOutputNote),
            "input": .array(input),
            "text": ["format": ["type": "json_schema", "name": .string(schemaName), "strict": true, "schema": schema]],
        ]
        if !tools.isEmpty { body["tools"] = .array(tools) }

        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/responses"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(JSONValue.object(body))

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
