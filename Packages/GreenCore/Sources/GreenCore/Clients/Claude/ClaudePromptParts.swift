import Foundation

/// Prompt text shared by the identify, alternatives and research calls, generated from the model
/// types so the prompt can never drift from the app's metric and category tables.
enum PromptParts {
    /// What each metric means and the unit/basis every number must use.
    static let metricDefinitions: String = MetricKey.allCases.map { metric in
        "- `\(metric.rawValue)` (\(metric.unit.symbol)): \(basis(of: metric))"
    }.joined(separator: "\n")

    /// The static category → applicable metrics table (spec §4).
    static let categoryTable: String = Category.allCases.map { category in
        "- `\(category.rawValue)`: " + category.applicableMetrics.map(\.rawValue).joined(separator: ", ")
    }.joined(separator: "\n")

    static func basis(of metric: MetricKey) -> String {
        switch metric {
        case .carbon: "cradle-to-grave footprint of ONE item as pictured (one unit or one serving), excluding use-phase electricity and a vehicle's fuel, which the app computes from power or distance and the local grid"
        case .water: "blue (consumptive) freshwater for one item/serving, liters"
        case .land: "land occupation for one item/serving, m²·year"
        case .powerOn: "electrical draw while on/in use, watts"
        case .standbyPower: "draw while plugged in but idle/standby/off, watts"
        case .yearlyElectricity: "electricity per year at typical use, kWh/year"
        case .lifespan: "expected years of service"
        case .repairability: "0-10 score in the style of the EU/French repairability index"
        case .plasticMass: "grams of plastic in the item plus its packaging"
        case .recyclablePercent: "percent of the item's mass realistically recyclable in curbside/e-waste streams, 0-100"
        case .decompositionTime: "years for the item's dominant material to break down if landfilled/littered"
        case .waterPollution: "eutrophication for one item/serving, grams PO₄-equivalent"
        }
    }

    static func vocabularyList(_ vocabulary: ReferenceVocabulary) -> String {
        """
        Reference keys (use the closest one; invent a new lowercase snake_case key only if nothing fits):
        - food_group: \(vocabulary.foodGroups.joined(separator: ", "))
        - device_type: \(vocabulary.deviceTypes.joined(separator: ", "))
        - material: \(vocabulary.materials.joined(separator: ", "))
        """
    }

    static let deferrableLoads: String = DeferrableLoadType.allCases.map { "`\($0.rawValue)` (\($0.displayName))" }
        .joined(separator: ", ")
}
