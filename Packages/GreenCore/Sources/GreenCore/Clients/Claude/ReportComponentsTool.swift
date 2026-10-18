import Foundation

/// The `report_components` tool (spec §5.3): its schema and the decoding of its input.
enum ReportComponentsTool {
    static let name = "report_components"

    static let definition: JSONValue = [
        "name": .string(name),
        "description": """
            Report every significant physical item in the photo with its identifiers, physical quantities, \
            default usage, deferrable-load type, last-resort estimate bounds and any clarifying question. \
            Do not report computed impact totals; the app computes impacts from databases and factor tables.
            """,
        "input_schema": SchemaParts.object([
            "scene_title": SchemaParts.string("1-3 word title for the scene, e.g. 'Desk setup', 'Lunch'."),
            "components": SchemaParts.array(of: component, "Distinct items, most environmentally significant first (max 8)."),
        ], required: ["scene_title", "components"]),
    ]

    /// The identify schema with `fallback_estimates` limited to one carbon value, which roughly halves the
    /// output (and the latency) of a call; the other metrics resolve from records and factor tables.
    static let carbonEstimateOnlySchema: JSONValue = {
        guard case .object(var root) = definition["input_schema"] ?? .null,
              case .object(var properties) = root["properties"] ?? .null,
              case .object(var components) = properties["components"] ?? .null,
              case .object(var item) = components["items"] ?? .null,
              case .object(var itemProperties) = item["properties"] ?? .null else { return definition["input_schema"] ?? .null }
        itemProperties["fallback_estimates"] = SchemaParts.array(of: SchemaParts.object([
            "metric": SchemaParts.enumeration(["carbon"], "Always carbon."),
            "value": SchemaParts.number("Best guess, kg CO2e for one item as pictured."),
            "low": SchemaParts.number("Plausible lower bound."),
            "high": SchemaParts.number("Plausible upper bound."),
        ], required: ["metric", "value", "low", "high"]), "Exactly one rough carbon estimate, used only if no record exists.")
        item["properties"] = .object(itemProperties)
        components["items"] = .object(item)
        properties["components"] = .object(components)
        root["properties"] = .object(properties)
        return .object(root)
    }()

    /// `definition` with `carbonEstimateOnlySchema`, used by the identify call.
    static let slimDefinition: JSONValue = {
        guard case .object(var fields) = definition else { return definition }
        fields["input_schema"] = carbonEstimateOnlySchema
        return .object(fields)
    }()

    static let component = SchemaParts.object([
        "name": SchemaParts.string("Item name, as specific as the identification: brand and model line first when confidence is medium or high, else a plain name such as '27-inch monitor', 'Beef burger', 'Cotton T-shirt'."),
        "category": SchemaParts.enumeration(SchemaParts.categories, "Category; decides which metrics apply."),
        "bounding_box": SchemaParts.object([
            "x": SchemaParts.number("Left edge, fraction of image width (0-1)."),
            "y": SchemaParts.number("Top edge, fraction of image height (0-1, origin top-left)."),
            "width": SchemaParts.number("Width, fraction of image width."),
            "height": SchemaParts.number("Height, fraction of image height."),
        ], required: ["x", "y", "width", "height"], description: "Tight box around the item in normalized image coordinates."),
        "identifiers": SchemaParts.identifyIdentifiers,
        "quantities": SchemaParts.quantities,
        "default_usage": SchemaParts.usage,
        "deferrable_load": SchemaParts.enumeration(DeferrableLoadType.allCases.map(\.rawValue),
            "Set when the item is, or is charged by, a load whose charging/running can be shifted in time; else null.",
            nullable: true),
        "fallback_estimates": SchemaParts.estimates,
        "needs_question": SchemaParts.array(of: question, "At most one question, only when the answer changes the footprint a lot."),
    ], required: ["name", "category", "bounding_box", "identifiers", "quantities", "default_usage",
                  "deferrable_load", "fallback_estimates", "needs_question"])

    static let question = SchemaParts.object([
        "id": SchemaParts.string("Stable snake_case id, e.g. 'hours_on', 'servings_per_week'."),
        "question": SchemaParts.string("Short, friendly question for the user."),
        "why_it_matters": SchemaParts.string("One sentence on why the answer changes the numbers."),
        "affected_metrics": SchemaParts.array(of: SchemaParts.enumeration(SchemaParts.metricKeys, "Metric key."),
                                              "Metrics the answer changes."),
        "options": SchemaParts.array(of: SchemaParts.object([
            "label": SchemaParts.string("Chip label, e.g. '~2 h', 'Weekly'."),
            "field": SchemaParts.enumeration(UsageField.askable.map(\.rawValue), "Usage field the answer sets.", nullable: true),
            "value": SchemaParts.nullableNumber("Value assigned to the field."),
        ], required: ["label", "field", "value"]), "2-4 answer chips."),
    ], required: ["id", "question", "why_it_matters", "affected_metrics", "options"])

    /// Decodes and sanitizes the tool input.
    static func parse(_ input: JSONValue) throws -> IdentifyResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload: Payload
        do {
            payload = try input.decode(Payload.self, decoder: decoder)
        } catch {
            throw GreenCoreError.invalidModelOutput("report_components input: \(error)")
        }
        let components = try payload.components.map { try $0.makeIdentified() }
        return IdentifyResponse(components: components, sceneTitle: payload.sceneTitle?.trimmedNonEmpty)
    }

    struct Payload: Decodable {
        var sceneTitle: String?
        var components: [ComponentPayload]
    }

    struct ComponentPayload: Decodable {
        var name: String
        var category: String
        var boundingBox: NormalizedRect
        var identifiers: IdentifiersPayload?
        var quantities: Quantities?
        var defaultUsage: UsageProfile?
        var deferrableLoad: String?
        var fallbackEstimates: [EstimatePayload]?
        var needsQuestion: [ComponentQuestion]?

        func makeIdentified() throws -> IdentifiedComponent {
            guard let name = name.trimmedNonEmpty else { throw GreenCoreError.invalidModelOutput("component without a name") }
            guard let category = Category(looseRawValue: category) else {
                throw GreenCoreError.invalidModelOutput("unknown category '\(self.category)' for \(name)")
            }
            return IdentifiedComponent(
                name: name, category: category, boundingBox: boundingBox.clamped,
                identifiers: identifiers?.identifiers ?? Identifiers(),
                quantities: quantities ?? Quantities(),
                defaultUsage: defaultUsage,
                deferrableLoad: deferrableLoad.flatMap(DeferrableLoadType.init(looseRawValue:)),
                estimates: EstimatePayload.table(fallbackEstimates ?? [], for: category),
                needsQuestion: (needsQuestion ?? []).filter { !$0.options.isEmpty })
        }
    }

    struct IdentifiersPayload: Decodable {
        var brand: String?
        var model: String?
        var modelLine: String?
        var confidence: String?
        var appearanceCues: String?
        var gtin: String?
        var materials: [MaterialShare]?
        var visibleText: String?

        var identifiers: Identifiers {
            let brand = brand?.trimmedNonEmpty
            return Identifiers(gtin: gtin.flatMap(GTINDigits.normalized), brand: brand, model: model?.trimmedNonEmpty,
                               modelLine: modelLine.flatMap { Self.line($0, brand: brand) },
                               confidence: confidence?.trimmedNonEmpty.flatMap { IdentificationConfidence(rawValue: $0.lowercased()) },
                               appearanceCues: appearanceCues?.trimmedNonEmpty,
                               materials: (materials ?? []).filter { $0.percent > 0 }, ocrText: visibleText?.trimmedNonEmpty)
        }

        /// The model line without a leading brand ("Apple MacBook Air" → "MacBook Air"), so one line always gives
        /// the same line key whether or not the answer repeated the brand.
        static func line(_ raw: String, brand: String?) -> String? {
            guard let line = raw.trimmedNonEmpty else { return nil }
            guard let brand, line.count > brand.count, line.lowercased().hasPrefix(brand.lowercased()),
                  line.dropFirst(brand.count).first?.isWhitespace == true else { return line }
            return line.dropFirst(brand.count).trimmingCharacters(in: .whitespaces).trimmedNonEmpty
        }
    }
}

/// `{metric, value, low, high}`; shared by identify, alternatives and research tools.
struct EstimatePayload: Decodable {
    var metric: String
    var value: Double
    var low: Double
    var high: Double

    /// Keeps applicable metrics only, ordering the bounds so low ≤ value ≤ high.
    static func table(_ items: [EstimatePayload], for category: Category) -> [MetricKey: EstimateRange] {
        var table: [MetricKey: EstimateRange] = [:]
        for item in items {
            guard let metric = MetricKey(rawValue: item.metric), category.applies(metric),
                  item.value.isFinite, item.low.isFinite, item.high.isFinite else { continue }
            let low = min(item.low, item.high, item.value), high = max(item.low, item.high, item.value)
            table[metric] = EstimateRange(value: item.value, low: max(low, 0), high: max(high, 0))
        }
        return table
    }
}

extension Category {
    /// Accepts raw values plus common spellings ("personal_care", "Electronics").
    init?(looseRawValue raw: String) {
        let key = raw.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
        let aliases: [String: Category] = ["electronics": .electronic, "drink": .food, "beverage": .food,
                                           "apparel": .clothing, "cosmetics": .personalCare]
        if let match = Category.allCases.first(where: { $0.rawValue.lowercased() == key }) {
            self = match
        } else if let alias = aliases[key] {
            self = alias
        } else {
            return nil
        }
    }
}

extension DeferrableLoadType {
    init?(looseRawValue raw: String) {
        let key = raw.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        guard let match = DeferrableLoadType.allCases.first(where: { $0.rawValue.lowercased() == key }) else { return nil }
        self = match
    }
}

enum GTINDigits {
    /// Digits only, accepted when the length is a valid GTIN-8/12/13/14.
    static func normalized(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return [8, 12, 13, 14].contains(digits.count) ? digits : nil
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
    }
}
