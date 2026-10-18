import Foundation

/// Which Open Food Facts record a brand and product name stand for, when food has no barcode (C4 of the image QA:
/// Lay's and Nerds Gummy Clusters have records, but only GTINs were looked up). A record is used only when it is a
/// confident match: the brand agrees, it names most of what identify named, and its variant does not conflict.
/// Variants are handled conservatively: a "Classic" bag never takes a Salt & Vinegar record or the reverse, and a
/// name with no flavour takes only a plain one, even though crisps' footprints barely differ by flavour.
public enum ProductNameMatch {
    /// Words that say nothing about which product it is: pack and size words, units and fillers.
    static let generic: Set<String> = [
        "and", "with", "the", "of", "a", "an", "in", "flavour", "flavor", "flavored", "flavoured", "pack", "bag",
        "box", "pouch", "wrapper", "packet", "can", "bottle", "jar", "carton", "tub", "multipack", "plastic", "size",
        "party", "family", "fun", "mini", "snack", "single", "serving", "share", "sharing", "ounce", "oz", "gram", "g",
        "gm", "ml", "l", "kg", "lb", "count", "ct", "piece",
    ]

    /// Words for the plain version of a product.
    static let base: Set<String> = ["classic", "original", "regular", "plain", "traditional"]

    /// Words that pick one variant of a product line: flavours, recipes and diet versions.
    static let variants: Set<String> = [
        "salt", "unsalted", "vinegar", "bbq", "barbecue", "barbeque", "sour", "cream", "onion", "cheddar", "cheese",
        "jalapeno", "chili", "chilli", "chile", "lime", "lemon", "honey", "mustard", "dill", "pickle", "ketchup",
        "spicy", "hot", "sweet", "masala", "pepper", "garlic", "ranch", "buffalo", "wasabi", "paprika", "herb",
        "tomato", "chicken", "beef", "pizza", "taco", "nacho", "salsa", "smoked", "mesquite", "truffle", "baked",
        "kettle", "wavy", "ridged", "light", "lite", "reduced", "low", "fat", "diet", "zero", "sugar", "free", "decaf",
        "strawberry", "chocolate", "vanilla", "caramel", "mint", "peppermint", "peanut", "butter", "almond",
        "hazelnut", "coconut", "cherry", "grape", "apple", "orange", "berry", "blueberry", "raspberry", "mango",
        "peach", "banana", "watermelon", "tropical", "fruit", "cinnamon", "coffee", "matcha", "rainbow", "dark",
        "milk", "white", "very", "wild",
    ]

    /// Share of identify's distinctive words a record must also name.
    static let minimumCoverage = 0.5

    /// The search text: the brand and the name without bracketed asides, the brand said once.
    static func query(brand: String, name: String) -> String? {
        let plainName = Identifiers.bracketFree(name).trimmingCharacters(in: .whitespaces)
        let brandWords = words(brand)
        guard !brandWords.isEmpty else { return plainName.trimmedNonEmpty }
        let nameWords = Set(words(plainName))
        let text = brandWords.allSatisfy(nameWords.contains) ? plainName : "\(brand) \(plainName)"
        return text.trimmingCharacters(in: .whitespaces).trimmedNonEmpty
    }

    /// The best confident match with a carbon figure, or nil. Several confident records usually share one Agribalyse
    /// category figure; the figure most of them agree on wins, so one mis-filed record does not decide, then the
    /// closest name, then the search's own order.
    public static func best(brand: String, name: String, among records: [ProductRecord]) -> ProductRecord? {
        let scored = records.enumerated().compactMap { offset, record -> (offset: Int, record: ProductRecord, score: Double)? in
            guard record.carbonKgPerKg != nil, let score = score(brand: brand, name: name, record: record) else { return nil }
            return (offset, record, score)
        }
        let groups = Dictionary(grouping: scored) { (($0.record.carbonKgPerKg ?? 0) * 1000).rounded() }
        let winner = groups.values.max { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return (lhs.map(\.score).max() ?? 0) < (rhs.map(\.score).max() ?? 0)
        }
        return winner?.min { lhs, rhs in lhs.score != rhs.score ? lhs.score > rhs.score : lhs.offset < rhs.offset }?.record
    }

    /// How well a record matches (higher is closer), or nil when it is not a confident match.
    static func score(brand: String, name: String, record: ProductRecord) -> Double? {
        let brandWords = Set(words(brand))
        guard !brandWords.isEmpty else { return nil }
        let recordName = words(record.name)
        let recordBrands = (record.brand ?? "").split(separator: ",").map { Set(words(String($0))) }
        let brandAgrees = recordBrands.contains { brandWords.isSubset(of: $0) } || brandWords.isSubset(of: Set(recordName))
        guard brandAgrees else { return nil }

        let query = Set(words(Identifiers.bracketFree(name))).subtracting(brandWords).subtracting(generic)
        let found = Set(recordName).subtracting(brandWords).subtracting(generic)
        guard query.subtracting(base).intersection(variants) == found.subtracting(base).intersection(variants) else {
            return nil
        }
        let distinctive = query.subtracting(base)
        guard !distinctive.isEmpty else {
            // "Lay's Classic": the plain product, which any record without a variant word is.
            return query.isEmpty ? nil : 0.5
        }
        let coverage = Double(distinctive.intersection(found).count) / Double(distinctive.count)
        guard coverage >= minimumCoverage else { return nil }
        let named = found.subtracting(base)
        let precision = named.isEmpty ? 1 : Double(named.intersection(distinctive).count) / Double(named.count)
        return coverage + precision / 2
    }

    /// Lowercased words without accents, apostrophes or numbers, roughly singular: "Lay's Salt & Vinegar Chips"
    /// → lay salt and vinegar chip, the same as "Lays salt and vinegar chips".
    static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        return folded.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.contains(where: \.isNumber) }
            .map(singular)
    }

    /// "chips" → "chip", "berries" → "berry", "potatoes" → "potato"; "salted" counts as "salt".
    static func singular(_ word: String) -> String {
        if word == "salted" { return "salt" }
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.hasSuffix("ss") { return word }
        return word.hasSuffix("s") ? String(word.dropLast()) : word
    }
}
