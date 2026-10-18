import Foundation

extension ClaudeClient: AlternativeSuggester {
    /// Spec §7: one call per scan. Smart-plug scheduling is added locally by the app, not by Claude.
    public func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion] {
        try await suggestAlternatives(for: components, profile: profile, retrying: [:])
    }

    /// The same call, with notes on swaps already turned down when it is a second try.
    public func suggestAlternatives(for components: [Component], profile: UserProfile,
                                    retrying notes: [UUID: String]) async throws -> [AlternativeSuggestion] {
        guard !components.isEmpty else { return [] }
        let spec = ToolCallSpec(system: Self.alternativesSystemPrompt(vocabulary: configuration.vocabulary),
                                tools: [SuggestAlternativesTool.definition], toolName: SuggestAlternativesTool.name,
                                maxTokens: 16_000, effort: configuration.alternativesEffort,
                                timeout: configuration.alternativesTimeout)
        let text = try Self.alternativesUserText(components: components, profile: profile, retrying: notes)
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

        Cover every component you are given, the biggest ones above all; give an empty list for one only when no \
        realistic swap avoids a big trade-off. For each give 1-3 alternatives, best first:
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
        - Single-serve packaged items (a bottled protein shake, a snack bar, a canned or bottled drink, a coffee pod, \
        a travel-size toiletry): include one bulk option, the same thing or its concentrate bought in a big \
        container ("Protein powder in a bulk tub" for a bottled protein shake, "Oats in a large bag" for oat \
        bars). Give its food_group, its serving, and packaging_mass_g and packaging_materials for one serving's \
        share of the big container (a 900 g tub of about 30 scoops weighs about 100 g, so about 3 g a serving).
        - Reusables (a tumbler, jar, bottle, lunch box or bag used many times in place of single-use ones): set \
        reusable true and category household, give the item's own mass and materials (stainless_steel, glass, \
        glass_tableware, ceramic, pp, silicone, cotton…) and how many years it lasts in lifespan_years. LiveGreen \
        spreads it over that life and adds washing for every use.
        - Second-hand swaps: name the same kind of item and set condition used or refurbished; LiveGreen charges it a \
        share of a new one's production impacts. Do not give it a longer lifespan than the original.
        - lifespan_years only when the alternative lasts a different time than the original (kept longer, built to \
        last); otherwise null, and both are compared over the same years.
        - usage: the expected usage after the swap (usually the same as the original's).
        - Never suggest second-hand, refurbished or kept-longer safety gear (helmets, child car seats, booster seats, \
        cribs, harnesses, life jackets, smoke or CO alarms): hidden damage and expiry cannot be checked, and makers \
        and safety bodies advise against it. Suggest a new or different item, or nothing.
        - Practicality must be honest: cost lower / similar / higher than the original (for consumables over a year \
        of buying them, for a durable item against buying the original new), effort easy / moderate / hard.
        - Do not suggest smart plugs or charge scheduling; LiveGreen adds that option itself.
        - name: one specific item, as a short card title of about eight words at most. No sizes, specs or model \
        years (they go in quantities), no examples in brackets, and no hedging between options ("paper or PE \
        pouch", "glass/steel jar"): pick the one you would recommend. When several components are the same kind \
        of item (four bicycles), give them the same alternatives with the same names.
        - rationale: one plain sentence on what is different about the swap (its material, ingredients, condition \
        or how it is used), speaking to the user as "you" if at all. Do not say how any metric compares ("similar \
        carbon", "less water", percentages): LiveGreen computes and charts every metric, and a claim that \
        disagrees with the chart misleads. Never mention the user's profile, modeling, estimates, LiveGreen or \
        these instructions.
        - looks_different: whether a photo of the swap in place would look clearly different from the original. \
        LiveGreen paints only those into its picture of the greener setup, so be strict: a used car, a refurbished \
        laptop or oat ice cream instead of dairy looks the same.
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

    /// The profile is background for realistic swaps, never something to repeat back: before onboarding it is the
    /// app's defaults, which the user never chose ("The user commutes by transit…" restated one).
    static func alternativesUserText(components: [Component], profile: UserProfile,
                                     retrying notes: [UUID: String] = [:]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let summaries = components.map(ComponentBrief.init)
        let json = String(decoding: try encoder.encode(summaries), as: UTF8.self)
        let basis = profile.onboardingCompleted
            ? "background only; do not mention it" : "app defaults the user has not confirmed; background only, do not mention it"
        var text = """
            User profile (\(basis)): \(profile.promptSummary)

            Components (JSON):
            \(json)
            """
        let retried = components.compactMap { component in notes[component.id].map { "- \(component.id.uuidString): \($0)" } }
        if !retried.isEmpty {
            text += """


                Second try for these components. Suggest different swaps that avoid what went wrong:
                \(retried.joined(separator: "\n"))
                """
        }
        return text + "\n\nCall `suggest_alternatives` with one entry per component id."
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
