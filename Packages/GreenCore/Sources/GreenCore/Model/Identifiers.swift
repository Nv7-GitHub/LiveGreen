import Foundation

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

/// How sure identify was of an item's most specific identifier (model, else model line, else brand).
public enum IdentificationConfidence: String, Codable, Sendable, Hashable, CaseIterable {
    /// Printed on the item or in the OCR text, or a design only that line has.
    case high
    /// Strong design cues pointing to one maker and line; the size or generation could differ.
    case medium
    /// A best guess from general styling.
    case low
}

/// What identifies a component: barcodes, brand/model, materials and raw OCR text.
public struct Identifiers: Codable, Sendable, Hashable {
    public var gtin: String?
    public var brand: String?
    /// An exact model number read off the item or the OCR text; exact-record lookups (ENERGY STAR, ASUS PCF) use it.
    public var model: String?
    /// The product line with the variant that changes specs, e.g. "MacBook Pro 14-inch (M-series)", when the item
    /// was recognized by its design or a printed line name rather than a model number. Spec research and line-level
    /// records use it; it is never looked up as a model number.
    public var modelLine: String?
    /// Confidence in the most specific of `model`, `modelLine` and `brand`; nil when identify did not say.
    public var confidence: IdentificationConfidence?
    /// What the identification rests on, in a few words (legible text, design cues).
    public var appearanceCues: String?
    public var materials: [MaterialShare]
    /// The container or wrapping thrown away after use (a drink's cup, lid and straw, a cleaner's bottle), the
    /// split that `Quantities.packagingMassG` weighs. Food, drinks and filled household or personal-care products
    /// only. Nil when identify did not say (older scans); the item's own materials then stand in.
    public var packagingMaterials: [MaterialShare]?
    public var ocrText: String?
    /// The kind of item when nothing more specific identifies it (see `genericKey(name:category:)`). Set by
    /// the scan pipeline, never by the AI, so the same kind of item resolves to the same numbers.
    public var genericKey: String?

    public init(gtin: String? = nil, brand: String? = nil, model: String? = nil, modelLine: String? = nil,
                confidence: IdentificationConfidence? = nil, appearanceCues: String? = nil,
                materials: [MaterialShare] = [], packagingMaterials: [MaterialShare]? = nil, ocrText: String? = nil,
                genericKey: String? = nil) {
        self.gtin = gtin
        self.brand = brand
        self.model = model
        self.modelLine = modelLine
        self.confidence = confidence
        self.appearanceCues = appearanceCues
        self.materials = materials
        self.packagingMaterials = packagingMaterials
        self.ocrText = ocrText
        self.genericKey = genericKey
    }

    /// Cache key: the GTIN, else `brand|model` lowercased; nil when neither is known (spec §5.4).
    public var cacheKey: String? {
        if let gtin, !gtin.isEmpty { return "gtin:\(gtin)" }
        guard let brand, let model, !brand.isEmpty, !model.isEmpty else { return nil }
        return "bm:\(brand.lowercased())|\(model.lowercased())"
    }

    /// The model line when identify was sure of it (high or medium confidence): what line-level spec research and
    /// records use. A low-confidence guess is not, and neither is a line whose confidence identify left out.
    public var confidentModelLine: String? {
        guard confidence == .high || confidence == .medium,
              let line = modelLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        return line
    }

    /// `category|brand|model line|size` for an item identified to its line but with no GTIN or model number, so a
    /// rescan of the same product gives the same numbers; nil otherwise. One line spans sizes whose numbers differ (a
    /// TV line from 43" to 85"), so the key holds the size (`sizeKey`) and there is none without it. Food and
    /// packaging never get one: as for their generic kinds, the portion or pack shown matters (a can and a 2 L bottle
    /// of one drink).
    public func lineKey(category: Category, quantities: Quantities) -> String? {
        guard cacheKey == nil, !Self.lineKeyExcludedCategories.contains(category), let brand = brand?.trimmedNonEmpty,
              let line = confidentModelLine, let size = Self.sizeKey(quantities) else { return nil }
        return "bl:\(category.rawValue)|\(brand.lowercased())|\(line.lowercased())|\(size)"
    }

    /// Key for the resolution cache and Monte Carlo seeds: `cacheKey`, else the line key, else the generic item key.
    public func resolutionKey(category: Category, quantities: Quantities) -> String? {
        cacheKey ?? lineKey(category: category, quantities: quantities) ?? genericKey.map { "item:\($0)" }
    }
}

extension Identifiers {
    /// Categories whose factor-model numbers rest on the AI's guessed mass and materials, which vary from call
    /// to call. Food is left out because colour words can name a different food (brown rice, green beans) and
    /// the portion shown matters; electronics come from device tables, scaled by screen size and usage.
    static let genericKeyCategories: Set<Category> = [.clothing, .household, .packaging, .personalCare, .vehicle]

    /// Words that describe how an item looks rather than what it is. Metal colours are kept: they can be the material.
    static let appearanceWords: Set<String> = [
        "black", "white", "grey", "gray", "red", "orange", "yellow", "green", "blue", "navy", "purple", "violet",
        "pink", "brown", "beige", "tan", "ivory", "khaki", "teal", "turquoise", "maroon", "burgundy", "coral",
        "lavender", "mint", "magenta", "indigo", "lilac", "taupe", "cyan", "dark", "pale", "bright", "neon",
        "pastel", "colorful", "colourful", "colored", "coloured", "multicolor", "multicolored", "multicoloured",
        "striped", "patterned", "plaid", "floral", "matte", "glossy", "shiny", "clear", "transparent",
        "a", "an", "the", "of", "pair",
    ]

    /// Where the item sits in the photo or how much of it shows: about the picture, not the product.
    static let positionWords: Set<String> = [
        "background", "foreground", "left", "right", "leftmost", "rightmost", "center", "centre", "middle", "rear",
        "behind", "distant", "far", "near", "nearby", "partial", "partially", "visible", "cropped",
    ]

    /// Size words and fillers. The mass that scales the numbers comes from the kind's lead item, so "compact SUV"
    /// and "SUV" are one kind.
    static let sizeWords: Set<String> = [
        "compact", "small", "smaller", "large", "larger", "big", "bigger", "medium", "mini", "tiny", "little", "huge",
        "jumbo", "giant", "oversized", "regular", "standard", "full", "half", "xs", "xl", "xxl",
        "drinking", "item", "object",
    ]

    /// Units of a printed size; dropped only right after a number ("22 fl oz", "2 pack").
    static let sizeUnitWords: Set<String> = [
        "fl", "oz", "ounce", "ml", "l", "liter", "litre", "g", "kg", "lb", "lbs", "pound", "gal", "gallon", "quart",
        "pint", "in", "inch", "cm", "mm", "pack", "ct", "count", "pc", "pcs", "piece", "x",
    ]

    /// How a lid or cap closes ("dome lid", "domed lid", "snap lid"): one kind of cup either way.
    static let closureWords: Set<String> = ["dome", "domed", "flat", "sealed", "snap", "sip", "screw", "twist", "flip"]

    /// Joining words that can be left dangling once the words around them are dropped.
    static let connectorWords: Set<String> = ["with", "in", "on", "at", "for", "from", "by"]

    /// Plurals the suffix rules get wrong, and words that only look plural.
    static let irregularPlurals: [String: String] = [
        "knives": "knife", "shelves": "shelf", "scarves": "scarf", "leaves": "leaf", "lenses": "lens", "buses": "bus",
        "cookies": "cookie", "hoodies": "hoodie", "beanies": "beanie", "onesies": "onesie", "brownies": "brownie",
        "smoothies": "smoothie", "children": "child", "feet": "foot", "teeth": "tooth",
    ]
    static let invariantWords: Set<String> = [
        "jeans", "pants", "shorts", "tights", "leggings", "trousers", "overalls", "pajamas", "pyjamas", "sweatpants",
        "scissors", "pliers", "tongs", "clothes", "lens", "series", "species", "canvas",
    ]

    /// Brands identify can return for an item with none.
    static let placeholderBrands: Set<String> = ["unknown", "generic", "none", "unbranded", "no brand", "n a", "na", "other"]

    /// Categories whose kind includes the brand: two makers' bicycles or SUVs are not one product, while packaging
    /// of one kind is alike whoever printed it.
    static let brandedKindCategories: Set<Category> = [.clothing, .household, .personalCare, .vehicle]

    /// Categories without line keys: a line of food or packaging spans portions and pack sizes.
    static let lineKeyExcludedCategories: Set<Category> = [.food, .packaging]

    /// The size that scales an item's numbers, rounded so one product reads alike across scans: the screen diagonal
    /// to the inch, else the mass to two significant figures; nil when neither is known.
    static func sizeKey(_ quantities: Quantities) -> String? {
        if let inches = quantities.screenSizeInches, inches > 0 { return "\(Int(inches.rounded()))in" }
        if let kg = quantities.massKg, kg > 0 { return String(format: "%.2gkg", kg) }
        return nil
    }

    /// A model line without a leading brand ("Apple MacBook Air" → "MacBook Air"), so one line always gives the same
    /// line key whether or not the brand was repeated; nil when nothing but the brand is left.
    public static func modelLine(_ raw: String, brand: String?) -> String? {
        guard let line = raw.trimmedNonEmpty else { return nil }
        guard let brand = brand?.trimmedNonEmpty else { return line }
        if line.caseInsensitiveCompare(brand) == .orderedSame { return nil }
        guard line.count > brand.count, line.lowercased().hasPrefix(brand.lowercased()),
              line.dropFirst(brand.count).first?.isWhitespace == true else { return line }
        return line.dropFirst(brand.count).trimmingCharacters(in: .whitespaces).trimmedNonEmpty
    }

    /// The item's kind: the words of its name that say what it is, lowercased and singular, so one kind reads alike
    /// across scans ("Blue backpack" and "Beige backpacks" → "backpack", "Clear plastic cups with domed lids" →
    /// "plastic cup with lid"). Left out: text in brackets or after a comma or spaced dash ("(partially visible)",
    /// ", 22 fl oz"), colour and finish words, where the item sits ("background", "left"), size words and printed
    /// sizes ("compact", "16 oz"), and how a lid closes. A brand leads the key outside packaging ("kia|suv"), so two
    /// makers' cars never share numbers. Nil outside `genericKeyCategories` or when no word is left.
    public static func genericKey(name: String, category: Category, brand: String? = nil) -> String? {
        guard genericKeyCategories.contains(category) else { return nil }
        let brandWords = brandedKindCategories.contains(category) ? brand.flatMap(brandWords) : nil
        let words = kindWords(descriptorFree(name), brandWords: brandWords ?? [])
            ?? kindWords(bracketFree(name), brandWords: brandWords ?? [])
        guard let words else { return nil }
        let kind = words.joined(separator: " ")
        return brandWords.map { "\($0.joined(separator: " "))|\(kind)" } ?? kind
    }

    /// The name without bracketed asides; an unclosed bracket runs to the end.
    static func bracketFree(_ name: String) -> String {
        var result = ""
        var depth = 0
        for character in name {
            switch character {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth = max(depth - 1, 0)
            default: if depth == 0 { result.append(character) }
            }
        }
        return result
    }

    /// The bracket-free name up to the first comma, semicolon or spaced dash: what follows describes the photo or
    /// the pack size ("Paper flyer, half sheet").
    static func descriptorFree(_ name: String) -> String {
        var head = bracketFree(name)
        for separator in [",", ";", " - ", " – ", " — "] {
            if let range = head.range(of: separator) { head = String(head[..<range.lowerBound]) }
        }
        return head
    }

    /// A brand's words for the key, or nil for no brand or a placeholder like "Unknown".
    static func brandWords(_ brand: String) -> [String]? {
        // "Levi's" splits into "levi" and "s"; the possessive is noise.
        let words = ReferenceKey.normalize(brand).split(separator: "_").map(String.init).filter { $0 != "s" }
        guard !words.isEmpty, !placeholderBrands.contains(words.joined(separator: " ")) else { return nil }
        return words
    }

    /// The words that name the kind, in order; nil when none is left.
    static func kindWords(_ text: String, brandWords: [String]) -> [String]? {
        let tokens = ReferenceKey.normalize(text).split(separator: "_").map(String.init)
        let brand = Set(brandWords.map(singular))
        var words: [String] = []
        var afterNumber = false
        var previousKept = false
        for (index, token) in tokens.enumerated() {
            let kept = previousKept
            previousKept = false
            if token.contains(where: \.isNumber) { afterNumber = true; continue }
            if afterNumber, sizeUnitWords.contains(token) { continue }
            afterNumber = false
            if token == "size" || token == "sized" {
                // "snack size", "travel-sized": the word before is a size too.
                if kept { words.removeLast() }
                continue
            }
            let next = tokens.indices.contains(index + 1) ? tokens[index + 1] : nil
            if closureWords.contains(token), let next, ["lid", "lids", "cap", "caps"].contains(next) { continue }
            if token == "s" || appearanceWords.contains(token) || positionWords.contains(token) || sizeWords.contains(token) {
                continue
            }
            let word = ["and", "w", "plus"].contains(token) ? "with" : singular(token)
            if brand.contains(word) || words.last == word { continue }
            words.append(word)
            previousKept = true
        }
        while let first = words.first, connectorWords.contains(first) { words.removeFirst() }
        while let last = words.last, connectorWords.contains(last) { words.removeLast() }
        return words.isEmpty ? nil : words
    }

    /// One word's singular: "cups" → "cup", "glasses" → "glass", "boxes" → "box", "batteries" → "battery".
    static func singular(_ word: String) -> String {
        if let singular = irregularPlurals[word] { return singular }
        guard word.count > 3, word.hasSuffix("s"), !invariantWords.contains(word) else { return word }
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if ["sses", "xes", "zes", "ches", "shes"].contains(where: { word.hasSuffix($0) }) { return String(word.dropLast(2)) }
        if ["ss", "us", "is"].contains(where: { word.hasSuffix($0) }) { return word }
        return String(word.dropLast())
    }
}
