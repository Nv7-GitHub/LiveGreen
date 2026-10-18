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

    static func nullableBoolean(_ description: String) -> JSONValue {
        ["type": ["boolean", "null"], "description": .string(description)]
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

    static func materialList(_ description: String) -> JSONValue {
        array(of: object([
            "material": string("Lowercase snake_case material key, e.g. cotton, polyester, aluminium, pet."),
            "percent": number("Share of the mass, 0-100."),
        ], required: ["material", "percent"]), description)
    }

    static let materials = materialList("Material split by mass; percentages should sum to ~100. Empty when unknown.")

    static let identifiers = identifiersSchema(brand: "Brand exactly as printed or recognizable; null if not visible.")

    /// Identify's identifiers: the brand may come from a legible logo or from distinctive design, the product line
    /// goes in `model_line` with a `confidence`, and `model` stays an exact printed model number. `appearance_cues`
    /// sorts first, so the evidence is written before the brand it supports. No example names: the fast models copy them.
    /// `packaging_materials` is optional, so items without packaging spend no output on it.
    static let identifyIdentifiers = identifiersSchema(
        brand: "Maker, from a legible logo or name or from distinctive design cues; null for unbranded or unrecognizable items.",
        model: "Exact model number as printed on the item or in the OCR hints; null if none is legible. Never guess one or derive it from the model line.",
        lineLevel: [
            "appearance_cues": nullableString("A few words on what identifies the maker and line (legible logo or text, distinctive design); null for plain unbranded goods."),
            "model_line": nullableString("Product line or family as the maker markets it, plus the size, generation or capacity the cues support. Not a model number. Null if unknown."),
            "confidence": enumeration(IdentificationConfidence.allCases.map(\.rawValue),
                "For the most specific of model, model_line and brand: high = printed or a design unique to that line; medium = strong design cues, variant uncertain; low = best guess.",
                nullable: true),
        ],
        optional: [
            "packaging_materials": materialList("Food, drinks and filled household or personal-care products: split of the packaging thrown away after use (cup, lid, straw, bottle, can, bag, wrapper), the packaging that packaging_mass_g weighs. Omit or leave empty when unpackaged."),
        ])

    static func identifiersSchema(brand: String,
                                  model: String = "Model number/name exactly as printed on the item or in the OCR hints; null if none is legible. Never guess one.",
                                  lineLevel: [String: JSONValue] = [:], optional: [String: JSONValue] = [:]) -> JSONValue {
        object([
            "brand": nullableString(brand),
            "model": nullableString(model),
            "gtin": nullableString("GTIN/EAN/UPC digits if a barcode hint or printed number belongs to this item; else null."),
            "materials": materials,
            "visible_text": nullableString("Short label text read from this item (energy label, care label, nutrition panel), if any."),
        ].merging(lineLevel) { _, line in line }.merging(optional) { _, extra in extra },
        required: ["brand", "model", "gtin", "materials"] + lineLevel.keys.sorted())
    }

    static let quantities = object([
        "mass_kg": nullableNumber("Mass of the item as pictured (one unit or one serving), kg."),
        "serving_kg": nullableNumber("Food only: mass of one serving, kg. A single drink, cup or snack pack is one serving."),
        "packaging_mass_g": nullableNumber("Mass of the packaging thrown away after use (cup, lid, straw, bottle, wrapper), g. Null when unpackaged; reusable dishes are not packaging."),
        "screen_size_inches": nullableNumber("Displays only: diagonal, inches."),
        "rated_power_w": nullableNumber("Rated or label wattage, W (prefer OCR wattage hints)."),
        "volume_liters": nullableNumber("Drinks/containers/appliances: volume, L."),
        "food_group": nullableString("Food only: reference food-group key for the food as served (see list in instructions)."),
        "device_type": nullableString("Electronics/appliances: reference device-type key (see list in instructions)."),
        "cooked": nullableBoolean("Food only: true when cooked from a dry grain, pasta or pulse (boiled rice, pasta, porridge, cooked or canned beans), so the mass includes absorbed water; else null."),
    ].merging(durableQuantities) { _, durable in durable }, required: ["mass_kg"])

    // MARK: Vehicles and household consumables

    /// Optional quantities for the vehicle model (`powertrain`) and for household consumables (`consumable`,
    /// `uses_per_container`), so other items spend no output on them.
    static let durableQuantities: [String: JSONValue] = [
        "powertrain": enumeration(Powertrain.allCases.map(\.rawValue),
            "Vehicles only: what drives it, from badges and design cues (no grille or tailpipe, a charge port); null otherwise.",
            nullable: true),
        "consumable": nullableBoolean("Household goods only: true when used up and replaced (cleaner, detergent, paper notebook, sponge, candle); else null."),
        "uses_per_container": nullableNumber("Consumables only: about how many uses one item lasts (sprays or treatments in a bottle, writing sessions in a notebook)."),
    ]

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
