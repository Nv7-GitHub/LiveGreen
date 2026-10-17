/// Claude model used for identify/alternatives/research (spec §2).
public enum ClaudeModel: String, Codable, Sendable, Hashable, CaseIterable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"

    /// API model id.
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .opus: "Claude Opus 5.5 (best)"
        case .sonnet: "Claude Sonnet 5.5 (faster)"
        }
    }
}
