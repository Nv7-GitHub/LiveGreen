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

        Greener means better across all of the item's metrics, weighted equally. Carbon is one metric among \
        equals, not the goal: LiveGreen scores each swap by its average improvement over every applicable metric \
        (carbon, water, land, water pollution, plastic, electricity, standby and on power, lifespan, \
        repairability, recyclability, decomposition time) and discards any swap that makes one of them clearly \
        worse (more than about 40%), however much it improves the others. So:
        - Prefer swaps that improve several metrics, or improve one while keeping the rest about the same.
        - Never suggest a swap with a big trade-off, e.g. less carbon but much more water, plastic, land or \
        power, or a much shorter life. Compare per year of doing the same job: a reusable cup replaces a year of \
        disposable ones.
        - If no swap for a component avoids big trade-offs, give fewer alternatives rather than a bad one.

        For each component give 1-3 alternatives, best first:
        - Same job for the user: a monitor is replaced by a monitor (more efficient, refurbished, or kept \
        longer), a beef burger by a lower-impact burger, a disposable cup by a reusable one. Behavior swaps \
        (e.g. "Line-dry instead of tumble-dry", "Buy this second-hand") are welcome when they are realistic.
        - Realistic for this user and their region today: no prototypes, nothing they would obviously reject \
        given their profile (e.g. no meat for a vegetarian).
        - Name a real, current product with brand and model only when you are confident it exists (this enables \
        exact ENERGY STAR and spec-sheet lookups); otherwise describe the product type and leave identifiers null.
        - Fill quantities for the alternative itself (mass, serving size, wattage, screen size, volume), its \
        identifiers.materials, and food_group / device_type with the reference keys: LiveGreen models the swap from \
        these with the same factor tables as the original, so they decide its numbers. A food swap must be a \
        different food (another food_group), a smaller serving or less packaging; the same food called local, \
        organic, seasonal or home-made has the same factors and is not a swap.
        - Reusables (a tumbler, jar, bottle, lunch box or bag used many times in place of single-use ones): set \
        reusable true and category household, give the item's own mass and materials (stainless_steel, glass, \
        glass_tableware, ceramic, pp, silicone, cotton…) and how many years it lasts in lifespan_years. LiveGreen \
        spreads it over that life and adds washing for every use.
        - Second-hand swaps: name the same kind of item and set condition used or refurbished; LiveGreen charges it a \
        share of a new one's production impacts. Do not give it a longer lifespan than the original.
        - lifespan_years only when the alternative lasts a different time than the original (kept longer, built to \
        last); otherwise null, and both are compared over the same years.
        - usage: the expected usage after the swap (usually the same as the original's).
        - Practicality must be honest: cost lower / similar / higher than the original, effort easy / moderate / hard.
        - Do not suggest smart plugs or charge scheduling; LiveGreen adds that option itself.
        - fallback_estimates: rough last-resort bounds for every metric applicable to the alternative's category, \
        used only where the factor tables have nothing. Estimate the alternative on its own, from its own mass and \
        materials, never by scaling the original's numbers, and on its own category's basis: food per serving, \
        packaging and personal care per single unit, durables (electronics, clothing, household goods and every \
        reusable) for one item over its whole life, made once, not per use.

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

            Components (JSON):
            \(json)

            Call `suggest_alternatives` with one entry per component id.
            """
    }

    /// What Claude sees about each component. Its resolved metrics are left out: given them, the model scaled the
    /// original's numbers down a few percent for a relabelled swap instead of describing the swap itself.
    struct ComponentBrief: Encodable {
        var id: String
        var name: String
        var category: String
        var identifiers: Identifiers
        var quantities: Quantities
        var usage: UsageProfile?

        /// Food is described per serving, as identify estimates it, so the swaps' fallback estimates come back per
        /// serving; the pipeline puts swaps for a per-pack item back on its pack (`Alternative.onBasis`).
        init(_ item: Component) {
            let component = FoodServing.servingView(of: item)
            id = component.id.uuidString
            name = component.name
            category = component.category.rawValue
            identifiers = component.identifiers
            quantities = component.quantities
            usage = component.usage
        }
    }
}
