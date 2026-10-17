import Foundation

/// Effort level for `output_config.effort`. On Claude Opus 5.5 / Sonnet 5.5 thinking is always on
/// and effort is the latency/depth control (sampling parameters such as temperature are rejected).
public enum ClaudeEffort: String, Codable, Sendable, Hashable, CaseIterable {
    case low, medium, high, xhigh, max
}

/// `POST /v1/messages` body. Content blocks are `JSONValue` so assistant turns (including
/// thinking blocks and their signatures) can be replayed exactly as received.
struct MessagesRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        var role: String
        var content: [JSONValue]
    }

    struct OutputConfig: Encodable, Sendable {
        var effort: ClaudeEffort
    }

    var model: String
    var maxTokens: Int
    var system: [JSONValue]
    var messages: [Message]
    var tools: [JSONValue]
    var toolChoice: JSONValue = ["type": "auto"]
    var outputConfig: OutputConfig
    /// `"default"` enables server-side refusal fallbacks (beta `server-side-fallback-2026-07-01`).
    var fallbacks: String?

    enum CodingKeys: String, CodingKey {
        case model, system, messages, tools, fallbacks
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case outputConfig = "output_config"
    }
}

/// The parts of a Messages API response the clients use.
struct MessagesResponse: Decodable, Sendable {
    var id: String
    var model: String
    var stopReason: String?
    var stopDetails: JSONValue?
    var content: [JSONValue]

    enum CodingKeys: String, CodingKey {
        case id, model, content
        case stopReason = "stop_reason"
        case stopDetails = "stop_details"
    }

    /// Client `tool_use` blocks with the given name.
    func toolUses(named name: String) -> [ToolUse] {
        content.compactMap { block in
            guard block["type"]?.string == "tool_use", block["name"]?.string == name,
                  let id = block["id"]?.string else { return nil }
            return ToolUse(id: id, input: block["input"] ?? .object([:]))
        }
    }

    /// Every client `tool_use` id (each needs a `tool_result` in the next user turn).
    var allToolUseIDs: [String] {
        content.compactMap { $0["type"]?.string == "tool_use" ? $0["id"]?.string : nil }
    }
}

struct ToolUse: Sendable {
    var id: String
    var input: JSONValue
}

/// `{"type":"error","error":{"type":…,"message":…}}`
struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable {
        var type: String
        var message: String
    }
    var error: Detail
}
