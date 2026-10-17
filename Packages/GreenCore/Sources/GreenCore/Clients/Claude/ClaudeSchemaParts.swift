import Foundation

/// JSON-schema fragments shared by the Claude tools. Tools are not `strict`: the identify schema has
/// far more optional fields than strict mode's 24-optional / 16-union limits allow, so inputs are
/// validated on decode and errors are sent back to Claude instead (see `ClaudeToolLoop`).
enum SchemaParts {
    static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    static func nullableString(_ description: String) -> JSONValue {
        ["type": ["string", "null"], "description": .string(description)]
    }

    static func number(_ description: String) -> JSONValue {
        ["type": "number", "description": .string(description)]
    }

    static func nullableNumber(_ description: String) -> JSONValue {
        ["type": ["number", "null"], "description": .string(description)]
    }

    static func enumeration(_ values: [String], _ description: String, nullable: Bool = false) -> JSONValue {
        let options = values.map(JSONValue.string) + (nullable ? [JSONValue.null] : [])
        return ["type": nullable ? ["string", "null"] : "string", "enum": .array(options),
                "description": .string(description)]
    }

    static func object(_ properties: [String: JSONValue], required: [String], description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": "object", "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)), "additionalProperties": false,
        ]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    static func array(of items: JSONValue, _ description: String) -> JSONValue {
        ["type": "array", "items": items, "description": .string(description)]
    }

    static let metricKeys = MetricKey.allCases.map(\.rawValue)
    static let categories = Category.allCases.map(\.rawValue)

    static let materials = array(of: object([
        "material": string("Lowercase snake_case material key, e.g. cotton, polyester, aluminium, pet."),
        "percent": number("Share of the item's mass, 0-100."),
    ], required: ["material", "percent"]), "Material split by mass; percentages should sum to ~100. Empty when unknown.")

    static let identifiers = object([
        "brand": nullableString("Brand exactly as printed or recognizable; null if not visible."),
        "model": nullableString("Model number/name exactly as printed on the item or in the OCR hints; null if none is legible. Never guess one."),
        "gtin": nullableString("GTIN/EAN/UPC digits if a barcode hint or printed number belongs to this item; else null."),
        "materials": materials,
        "visible_text": nullableString("Short label text read from this item (energy label, care label, nutrition panel), if any."),
    ], required: ["brand", "model", "gtin", "materials"])

    static let quantities = object([
        "mass_kg": nullableNumber("Mass of the item as pictured (one unit or one serving), kg."),
        "serving_kg": nullableNumber("Food only: mass of one serving, kg."),
        "packaging_mass_g": nullableNumber("Mass of packaging around/with the item, g."),
        "screen_size_inches": nullableNumber("Displays only: diagonal, inches."),
        "rated_power_w": nullableNumber("Rated or label wattage, W (prefer OCR wattage hints)."),
        "volume_liters": nullableNumber("Drinks/containers/appliances: volume, L."),
        "food_group": nullableString("Food only: reference food-group key (see list in instructions)."),
        "device_type": nullableString("Electronics/appliances: reference device-type key (see list in instructions)."),
    ], required: ["mass_kg"])

    static let usage = object([
        "hours_on_per_day": nullableNumber("Hours per day actively on/in use."),
        "standby_hours_per_day": nullableNumber("Hours per day plugged in but idle/standby."),
        "servings_per_week": nullableNumber("Food: servings per week for this person."),
        "wears_per_year": nullableNumber("Clothing: wears per year."),
        "uses_per_week": nullableNumber("Single-use or household items: uses per week."),
        "charges_per_week": nullableNumber("Battery devices/chargers: full charges per week."),
    ], required: [], description: "Typical usage for this user; only the fields relevant to the category.")

    static let estimates = array(of: object([
        "metric": enumeration(metricKeys, "Metric key."),
        "value": number("Best guess in the metric's canonical unit."),
        "low": number("Plausible lower bound (~5th percentile)."),
        "high": number("Plausible upper bound (~95th percentile)."),
    ], required: ["metric", "value", "low", "high"]),
        "Last-resort rough bounds for each applicable metric, used only if no database, spec sheet or factor model resolves it.")
}
