/// Claude model used for identify/alternatives/research (spec §2).
public enum ClaudeModel: String, Codable, Sendable, Hashable, CaseIterable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"

    /// API model id.
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .opus: "Claude Opus 5.5 (slower)"
        case .sonnet: "Claude Sonnet 5.5 (fast)"
        }
    }

    /// The `thinking` setting with no extended thinking, or nil when the model has none: Sonnet 5.5 rejects
    /// `disabled` and takes `between_tools` (effort `high` or below); Opus 5.5 always thinks, so effort is its
    /// only latency control.
    var thinkingOff: JSONValue? {
        switch self {
        case .sonnet: ["type": "between_tools"]
        case .opus: nil
        }
    }
}
