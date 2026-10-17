import Foundation

/// Suggests 1–3 greener alternatives per component (spec §7: one Claude call with a forced
/// `suggest_alternatives` tool). Returned alternatives carry identifiers/quantities, not metrics;
/// they are resolved through the evidence ladder afterwards.
public protocol AlternativeSuggester: Sendable {
    func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion]
}

/// Alternatives for one component.
public struct AlternativeSuggestion: Codable, Sendable, Hashable {
    public var componentID: UUID
    public var alternatives: [Alternative]

    public init(componentID: UUID, alternatives: [Alternative]) {
        self.componentID = componentID
        self.alternatives = alternatives
    }
}
