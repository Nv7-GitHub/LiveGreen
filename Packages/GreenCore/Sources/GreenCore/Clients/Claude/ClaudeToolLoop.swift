import Foundation

/// One "make Claude call this tool and give me its input" exchange.
///
/// Claude Opus 5.5 and Sonnet 5.5 reject a forced `tool_choice` (`any` / `tool`) with a 400, so the
/// tool is requested with `tool_choice: auto` plus an explicit instruction, and the loop checks the
/// call happened: it nudges once when Claude answers in text, returns decoding errors to Claude as an
/// `is_error` tool result so it can correct its input, resumes `pause_turn` (server tools), and
/// retries once with a larger `max_tokens` when the output was cut off.
struct ToolCallSpec: Sendable {
    var system: String
    /// The client tool first, then any server tools (`web_search`, `web_fetch`).
    var tools: [JSONValue]
    var toolName: String
    var maxTokens: Int
    var effort: ClaudeEffort
    var timeout: Double
    /// Skip extended thinking where the model allows it (Sonnet 5.5 `between_tools`), for latency.
    var thinkingOff = false

    var nudge: String {
        "Respond only by calling the `\(toolName)` tool now, with input that matches its schema exactly."
    }
}

extension ClaudeClient {
    static let maxToolTurns = 5
    static let maxTokensCeiling = 32_000

    func runTool<T: Sendable>(_ spec: ToolCallSpec, userContent: [JSONValue],
                              parse: @escaping @Sendable (_ input: JSONValue, _ transcript: [JSONValue]) throws -> T)
        async throws -> T {
        try await withDeadline(seconds: spec.timeout) {
            try await toolLoop(spec, userContent: userContent, parse: parse)
        }
    }

    private func toolLoop<T: Sendable>(_ spec: ToolCallSpec, userContent: [JSONValue],
                                       parse: @Sendable (JSONValue, [JSONValue]) throws -> T) async throws -> T {
        var messages = [MessagesRequest.Message(role: "user", content: userContent)]
        var maxTokens = spec.maxTokens
        var transcript: [JSONValue] = []
        var lastProblem = "no tool call"

        for _ in 0..<Self.maxToolTurns {
            let response = try await send(request(spec, messages: messages, maxTokens: maxTokens), timeout: spec.timeout)
            transcript += response.content

            switch response.stopReason {
            case "refusal":
                let category = response.stopDetails?["category"]?.string ?? "unspecified"
                throw GreenCoreError.invalidModelOutput("Claude declined the request (\(category)).")
            case "max_tokens":
                guard maxTokens < Self.maxTokensCeiling else {
                    throw GreenCoreError.invalidModelOutput("Output exceeded max_tokens (\(maxTokens)).")
                }
                maxTokens = min(maxTokens * 2, Self.maxTokensCeiling)
                continue
            case "pause_turn":
                messages.append(.init(role: "assistant", content: response.content))
                continue
            default:
                break
            }

            messages.append(.init(role: "assistant", content: response.content))
            guard let call = response.toolUses(named: spec.toolName).first else {
                messages.append(.init(role: "user", content: [["type": "text", "text": .string(spec.nudge)]]))
                continue
            }
            do {
                return try parse(call.input, transcript)
            } catch {
                lastProblem = "\(error)"
                messages.append(.init(role: "user", content: Self.errorResults(
                    for: response.allToolUseIDs, failing: call.id, problem: lastProblem)))
            }
        }
        throw GreenCoreError.invalidModelOutput("No valid `\(spec.toolName)` call: \(lastProblem)")
    }

    func request(_ spec: ToolCallSpec, messages: [MessagesRequest.Message], maxTokens: Int) -> MessagesRequest {
        MessagesRequest(
            model: configuration.model.id,
            maxTokens: maxTokens,
            system: [["type": "text", "text": .string(spec.system), "cache_control": ["type": "ephemeral"]]],
            messages: messages,
            tools: spec.tools,
            outputConfig: .init(effort: spec.effort),
            thinking: spec.thinkingOff ? configuration.model.thinkingOff : nil,
            fallbacks: configuration.serverSideFallbacks ? "default" : nil)
    }

    /// One `tool_result` per `tool_use` id: the failing call gets the validation problem.
    private static func errorResults(for ids: [String], failing failingID: String, problem: String) -> [JSONValue] {
        ids.map { id in
            let text = id == failingID
                ? "The input did not match the schema: \(problem). Call the tool again with corrected input."
                : "Ignored: make a single call."
            return ["type": "tool_result", "tool_use_id": .string(id), "is_error": true, "content": .string(text)]
        }
    }
}
