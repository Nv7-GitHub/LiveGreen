import Foundation

/// Suggests 1–3 greener alternatives per component (spec §7: one Claude call with a forced
/// `suggest_alternatives` tool). Returned alternatives carry identifiers/quantities, not metrics;
/// they are resolved through the evidence ladder afterwards.
public protocol AlternativeSuggester: Sendable {
    func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion]

    /// A second try for components whose first swaps were all turned down or never came (S10 of the image QA), with
    /// a note per component id on what was wrong, so the suggester can name something else.
    func suggestAlternatives(for components: [Component], profile: UserProfile,
                             retrying notes: [UUID: String]) async throws -> [AlternativeSuggestion]
}

extension AlternativeSuggester {
    /// Suggesters that cannot take notes just ask again.
    public func suggestAlternatives(for components: [Component], profile: UserProfile,
                                    retrying notes: [UUID: String]) async throws -> [AlternativeSuggestion] {
        try await suggestAlternatives(for: components, profile: profile)
    }
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
