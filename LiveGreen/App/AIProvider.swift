import Foundation

/// Which model runs identify, alternatives and spec research. The greener image always uses Grok.
nonisolated enum AIProvider: String, Codable, CaseIterable, Sendable {
    case grok
    case claude

    var displayName: String {
        switch self {
        case .grok: "Grok (xAI)"
        case .claude: "Claude (Anthropic)"
        }
    }

    /// The key the analysis calls need.
    var key: SecretKey {
        switch self {
        case .grok: .xai
        case .claude: .anthropic
        }
    }
}
