import Foundation

extension ClaudeClient: AlternativeSuggester {
    /// Spec §7: one call per scan. Smart-plug scheduling is added locally by the app, not by Claude.
    public func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion] {
        guard !components.isEmpty else { return [] }
        let spec = ToolCallSpec(system: Self.alternativesSystemPrompt(vocabulary: configuration.vocabulary),
                                tools: [SuggestAlternativesTool.definition], toolName: SuggestAlternativesTool.name,
                                maxTokens: 16_000, effort: configuration.alternativesEffort,
                                timeout: configuration.alternativesTimeout)
        let text = try Self.alternativesUserText(components: components, profile: profile)
        return try await runTool(spec, userContent: [["type": "text", "text": .string(text)]]) { input, _ in
            try SuggestAlternativesTool.parse(input, components: components)
        }
    }

    static func alternativesSystemPrompt(vocabulary: ReferenceVocabulary) -> String {
        """
        You suggest greener swaps for the components of a LiveGreen scan by calling the `suggest_alternatives` \
        tool exactly once, covering every component you are given.

        LiveGreen runs every alternative through the same evidence pipeline as the original (product databases, \
        cited spec sheets, factor tables × quantities), so comparisons are like-for-like. Your job is to name \
        alternatives precisely enough to be looked up or modeled, not to compute their impacts.

        For each component give 1-3 alternatives, best first:
        - Same job for the user: a monitor is replaced by a monitor (more efficient, refurbished, or kept \
        longer), a beef burger by a lower-impact burger, a disposable cup by a reusable one. Behavior swaps \
        (e.g. "Line-dry instead of tumble-dry", "Buy this second-hand") are welcome when they are realistic.
        - Realistic for this user and their region today: no prototypes, nothing they would obviously reject \
        given their profile (e.g. no meat for a vegetarian).
        - Name a real, current product with brand and model only when you are confident it exists (this enables \
        exact ENERGY STAR and spec-sheet lookups); otherwise describe the product type and leave identifiers null.
        - Fill quantities like for the original (mass, serving size, wattage, screen size, volume, materials), and \
        set food_group / device_type with the reference keys so factor tables apply.
        - usage: the expected usage after the swap (usually the same as the original's).
        - Practicality must be honest: cost lower / similar / higher than the original, effort easy / moderate / hard.
        - Do not suggest smart plugs or charge scheduling; LiveGreen adds that option itself.
        - fallback_estimates: rough last-resort bounds for every metric applicable to the alternative's category, \
        in the same units and basis as the original's.

        \(PromptParts.vocabularyList(vocabulary))

        Metric units and basis:
        \(PromptParts.metricDefinitions)
        """
    }

    static func alternativesUserText(components: [Component], profile: UserProfile) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let summaries = components.map(ComponentBrief.init)
        let json = String(decoding: try encoder.encode(summaries), as: UTF8.self)
        return """
            User profile: \(profile.promptSummary)

            Components (JSON; current metric values are in canonical units, where already resolved):
            \(json)

            Call `suggest_alternatives` with one entry per component id.
            """
    }

    /// What Claude sees about each component.
    struct ComponentBrief: Encodable {
        var id: String
        var name: String
        var category: String
        var identifiers: Identifiers
        var quantities: Quantities
        var usage: UsageProfile?
        var currentMetrics: [String: Double]

        init(_ component: Component) {
            id = component.id.uuidString
            name = component.name
            category = component.category.rawValue
            identifiers = component.identifiers
            quantities = component.quantities
            usage = component.usage
            currentMetrics = Dictionary(uniqueKeysWithValues: component.metrics.map { ($0.key.rawValue, $0.value.value) })
        }
    }
}
