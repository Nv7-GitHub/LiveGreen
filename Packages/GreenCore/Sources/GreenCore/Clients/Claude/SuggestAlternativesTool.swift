import Foundation

/// The `suggest_alternatives` tool (spec §7): its schema and the decoding of its input.
enum SuggestAlternativesTool {
    static let name = "suggest_alternatives"
    static let maxPerComponent = 3

    static let definition: JSONValue = [
        "name": .string(name),
        "description": """
            Report 1-3 greener alternatives for each listed component, each better across all applicable metrics \
            weighted equally (not carbon first) with no metric clearly worse, with identifiers or quantities \
            precise enough for LiveGreen to look up or model its impacts, a one-sentence rationale and an honest \
            practicality rating.
            """,
        "input_schema": SchemaParts.object([
            "suggestions": SchemaParts.array(of: SchemaParts.object([
                "component_id": SchemaParts.string("The id of the component exactly as given."),
                "alternatives": SchemaParts.array(of: alternative, "1-3 alternatives, best overall first."),
            ], required: ["component_id", "alternatives"]), "One entry per component."),
        ], required: ["suggestions"]),
    ]

    static let alternative = SchemaParts.object([
        "name": SchemaParts.string("Specific swap, e.g. 'Refurbished Dell P2722H monitor', 'Lentil burger', 'Reusable steel cup'."),
        "category": SchemaParts.enumeration(SchemaParts.categories, "Category of the alternative."),
        "rationale": SchemaParts.string("One plain sentence on why it is greener overall. No invented statistics."),
        "cost": SchemaParts.enumeration(Practicality.CostTier.allCases.map(\.rawValue), "Upfront or ongoing cost versus the original."),
        "effort": SchemaParts.enumeration(Practicality.Effort.allCases.map(\.rawValue), "Effort to switch."),
        "identifiers": SchemaParts.identifiers,
        "quantities": SchemaParts.quantities,
        "usage": SchemaParts.usage,
        "condition": SchemaParts.enumeration(Alternative.Condition.allCases.map(\.rawValue),
            "new, or used / refurbished when the swap is buying the item second-hand."),
        "reusable": ["type": "boolean", "description": """
            True for a durable item used again and again in place of single-use ones (a steel tumbler or glass jar \
            for disposable cups, a cloth bag for plastic bags). Scored as a household item over its whole life.
            """],
        "lifespan_years": SchemaParts.nullableNumber("""
            Years the alternative serves when that differs from the original's (kept longer, built to last, or a \
            reusable's life). Null when it lasts about as long; a used or refurbished item is compared over the \
            original's years.
            """),
        "fallback_estimates": SchemaParts.estimates,
    ], required: ["name", "category", "rationale", "cost", "effort", "identifiers", "quantities", "usage", "condition",
                  "reusable", "lifespan_years", "fallback_estimates"])

    static func parse(_ input: JSONValue, components: [Component]) throws -> [AlternativeSuggestion] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload: Payload
        do {
            payload = try input.decode(Payload.self, decoder: decoder)
        } catch {
            throw GreenCoreError.invalidModelOutput("suggest_alternatives input: \(error)")
        }
        let known = Dictionary(uniqueKeysWithValues: components.map { ($0.id.uuidString.lowercased(), $0) })
        var merged: [UUID: [Alternative]] = [:]
        for suggestion in payload.suggestions {
            guard let component = known[suggestion.componentId.lowercased()] else { continue }
            merged[component.id, default: []] += try suggestion.alternatives.map { try $0.makeAlternative(original: component) }
        }
        return components.compactMap { component in
            guard let alternatives = merged[component.id], !alternatives.isEmpty else { return nil }
            return AlternativeSuggestion(componentID: component.id, alternatives: Array(alternatives.prefix(maxPerComponent)))
        }
    }

    struct Payload: Decodable {
        var suggestions: [SuggestionPayload]
    }

    struct SuggestionPayload: Decodable {
        var componentId: String
        var alternatives: [AlternativePayload]
    }

    struct AlternativePayload: Decodable {
        var name: String
        var category: String
        var rationale: String
        var cost: String
        var effort: String
        var identifiers: ReportComponentsTool.IdentifiersPayload?
        var quantities: Quantities?
        var usage: UsageProfile?
        var condition: String?
        var reusable: Bool?
        var lifespanYears: Double?
        var fallbackEstimates: [EstimatePayload]?

        /// A condition or reuse flag left out is read from the name ("Used …", "Reusable …"). A reusable is filed
        /// as household before its estimates are kept, so its lifespan estimate is not dropped as a packaging one.
        func makeAlternative(original: Component) throws -> Alternative {
            guard let name = name.trimmedNonEmpty else { throw GreenCoreError.invalidModelOutput("alternative without a name") }
            let isReusable = reusable ?? name.lowercased().contains("reusable")
            let category = Alternative.scoredCategory(Category(looseRawValue: category) ?? original.category,
                                                      isReusable: isReusable)
            return Alternative(
                name: name, category: category,
                identifiers: identifiers?.identifiers ?? Identifiers(),
                quantities: quantities ?? Quantities(),
                usage: usage ?? original.usage,
                rationale: rationale.trimmedNonEmpty ?? "",
                practicality: Practicality(cost: Practicality.CostTier(rawValue: cost.lowercased()) ?? .similar,
                                           effort: Practicality.Effort(rawValue: effort.lowercased()) ?? .moderate),
                fallbackEstimates: EstimatePayload.table(fallbackEstimates ?? [], for: category),
                condition: condition.flatMap { Alternative.Condition(rawValue: $0.lowercased()) } ?? Alternative.Condition(name: name),
                isReusable: isReusable,
                lifespanYears: lifespanYears.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
        }
    }
}
