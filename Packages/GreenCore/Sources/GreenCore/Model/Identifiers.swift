/// A material and its share of an item's mass.
public struct MaterialShare: Codable, Sendable, Hashable {
    public var material: String
    /// 0–100.
    public var percent: Double

    public init(material: String, percent: Double) {
        self.material = material
        self.percent = percent
    }
}

/// What identifies a component: barcodes, brand/model, materials and raw OCR text.
public struct Identifiers: Codable, Sendable, Hashable {
    public var gtin: String?
    public var brand: String?
    public var model: String?
    public var materials: [MaterialShare]
    public var ocrText: String?
    /// The kind of item when nothing more specific identifies it (see `genericKey(name:category:)`). Set by
    /// the scan pipeline, never by the AI, so the same kind of item resolves to the same numbers.
    public var genericKey: String?

    public init(gtin: String? = nil, brand: String? = nil, model: String? = nil,
                materials: [MaterialShare] = [], ocrText: String? = nil, genericKey: String? = nil) {
        self.gtin = gtin
        self.brand = brand
        self.model = model
        self.materials = materials
        self.ocrText = ocrText
        self.genericKey = genericKey
    }

    /// Cache key: the GTIN, else `brand|model` lowercased; nil when neither is known (spec §5.4).
    public var cacheKey: String? {
        if let gtin, !gtin.isEmpty { return "gtin:\(gtin)" }
        guard let brand, let model, !brand.isEmpty, !model.isEmpty else { return nil }
        return "bm:\(brand.lowercased())|\(model.lowercased())"
    }

    /// Key for the resolution cache and Monte Carlo seeds: `cacheKey`, else the generic item key.
    public var resolutionKey: String? {
        cacheKey ?? genericKey.map { "item:\($0)" }
    }
}

extension Identifiers {
    /// Categories whose factor-model numbers rest on the AI's guessed mass and materials, which vary from call
    /// to call. Food is left out because colour words can name a different food (brown rice, green beans) and
    /// the portion shown matters; electronics come from device tables, scaled by screen size and usage.
    static let genericKeyCategories: Set<Category> = [.clothing, .household, .packaging, .personalCare]

    /// Words that describe how an item looks rather than what it is. Metal colours are kept: they can be the material.
    static let appearanceWords: Set<String> = [
        "black", "white", "grey", "gray", "red", "orange", "yellow", "green", "blue", "navy", "purple", "violet",
        "pink", "brown", "beige", "tan", "ivory", "khaki", "teal", "turquoise", "maroon", "burgundy", "coral",
        "lavender", "mint", "magenta", "indigo", "lilac", "taupe", "cyan", "dark", "pale", "bright", "neon",
        "pastel", "colorful", "colourful", "colored", "coloured", "multicolor", "multicolored", "multicoloured",
        "striped", "patterned", "plaid", "floral", "matte", "glossy", "shiny", "clear", "transparent",
        "a", "an", "the", "of", "pair",
    ]

    /// The item's kind: its name lowercased, without colour or finish words, each word singular ("Blue backpack"
    /// and "Beige backpacks" → "backpack"). Nil outside `genericKeyCategories` or when no word is left.
    public static func genericKey(name: String, category: Category) -> String? {
        guard genericKeyCategories.contains(category) else { return nil }
        let words = ReferenceKey.normalize(name).split(separator: "_").map(String.init)
            .filter { !appearanceWords.contains($0) }
            .map { $0.count > 3 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
