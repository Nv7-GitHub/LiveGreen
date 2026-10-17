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
        "fallback_estimates": SchemaParts.estimates,
    ], required: ["name", "category", "rationale", "cost", "effort", "identifiers", "quantities", "usage", "fallback_estimates"])

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
        var fallbackEstimates: [EstimatePayload]?

        func makeAlternative(original: Component) throws -> Alternative {
            guard let name = name.trimmedNonEmpty else { throw GreenCoreError.invalidModelOutput("alternative without a name") }
            let category = Category(looseRawValue: category) ?? original.category
            return Alternative(
                name: name, category: category,
                identifiers: identifiers?.identifiers ?? Identifiers(),
                quantities: quantities ?? Quantities(),
                usage: usage ?? original.usage,
                rationale: rationale.trimmedNonEmpty ?? "",
                practicality: Practicality(cost: Practicality.CostTier(rawValue: cost.lowercased()) ?? .similar,
                                           effort: Practicality.Effort(rawValue: effort.lowercased()) ?? .moderate),
                fallbackEstimates: EstimatePayload.table(fallbackEstimates ?? [], for: category))
        }
    }
}
