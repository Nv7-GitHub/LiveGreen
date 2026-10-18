import Foundation

/// Open Food Facts v2 product response. Fields are read through `JSONValue` because OFF mixes numbers
/// and numeric strings (e.g. `product_quantity`, `weight_measured`).
struct OFFProductPayload: Decodable {
    var status: Int?
    var product: JSONValue?

    func record(gtin: String, sourceURL: URL) -> ProductRecord? {
        guard status != 0, let product else { return nil }
        return Self.record(from: product, gtin: gtin, sourceURL: sourceURL)
    }

    /// A product object as the product API and the search service return it. `brands` is a comma-separated string
    /// from the product API (its first brand is kept) and a list from search (all kept, comma-separated, so a name
    /// match can check each).
    static func record(from product: JSONValue, gtin: String, sourceURL: URL, allBrands: Bool = false) -> ProductRecord? {
        guard product.object != nil else { return nil }
        let name = product["product_name"]?.string?.trimmedNonEmpty
            ?? product["product_name_en"]?.string?.trimmedNonEmpty ?? "Product \(gtin)"
        let brands = (product["brands"]?.array?.compactMap(\.string)
            ?? product["brands"]?.string?.split(separator: ",").map(String.init) ?? [])
            .compactMap { $0.trimmingCharacters(in: .whitespaces).trimmedNonEmpty }
        let brand = allBrands ? brands.joined(separator: ", ").trimmedNonEmpty : brands.first
        let agribalyse = product["ecoscore_data"]?["agribalyse"]
        return ProductRecord(
            gtin: gtin, name: name, brand: brand, category: .food,
            netMassKg: Self.massKg(quantity: product["product_quantity"], unit: product["product_quantity_unit"]?.string),
            servingKg: Self.massKg(quantity: product["serving_quantity"], unit: product["serving_quantity_unit"]?.string),
            carbonKgPerKg: agribalyse?["co2_total"]?.double,
            stageShares: agribalyse.map(Self.stageShares) ?? [:],
            packaging: (product["packagings"]?.array ?? []).compactMap(Self.packagingPart),
            sourceURL: sourceURL,
            foodGroup: Self.foodGroup(categories: (product["categories_tags"]?.array ?? []).compactMap(\.string)),
            imageURL: (product["image_front_url"]?.string ?? product["image_url"]?.string).flatMap(URL.init(string:)))
    }

    /// OFF category tags → reference food group, for the drinks the factor table covers directly. Waters are
    /// checked first because carbonated waters are also tagged as carbonated drinks.
    static func foodGroup(categories: [String]) -> String? {
        let tags = Set(categories.map { $0.lowercased() })
        if !tags.isDisjoint(with: ["en:waters", "en:carbonated-waters", "en:mineral-waters", "en:spring-waters",
                                   "en:flavored-waters", "en:unsweetened-waters"]) {
            return "bottled_water"
        }
        if !tags.isDisjoint(with: ["en:sodas", "en:colas", "en:carbonated-soft-drinks", "en:soft-drinks"]) {
            return "soft_drinks"
        }
        return nil
    }

    /// Converts `product_quantity` + unit to kg (liquids at ~1 kg/L).
    static func massKg(quantity: JSONValue?, unit: String?) -> Double? {
        guard let amount = quantity?.double, amount > 0 else { return nil }
        switch unit?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "kg", "l": return amount
        case "cl": return amount / 100
        case "mg": return amount / 1_000_000
        default: return amount / 1_000 // g, ml, or unspecified (OFF normalizes to g/ml)
        }
    }

    /// Agribalyse per-kg stage values → fractions of the total, mapped onto LiveGreen's lifecycle stages.
    static func stageShares(_ agribalyse: JSONValue) -> [LifecycleStage: Double] {
        let value = { (key: String) in max(agribalyse[key]?.double ?? 0, 0) }
        let raw: [LifecycleStage: Double] = [
            .materials: value("co2_agriculture"),
            .manufacturing: value("co2_processing") + value("co2_packaging"),
            .transport: value("co2_transportation") + value("co2_distribution"),
            .use: value("co2_consumption"),
        ]
        let total = raw.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return raw.filter { $0.value > 0 }.mapValues { $0 / total }
    }

    static func packagingPart(_ item: JSONValue) -> PackagingPart? {
        guard let rawMaterial = item["material"]?.string else { return nil }
        let material = OFFTags.strip(rawMaterial)
        let units = max(item["number_of_units"]?.double ?? 1, 1)
        let mass = (item["weight_measured"]?.double ?? item["weight_specified"]?.double).map { $0 * units }
        return PackagingPart(material: material, massG: mass, isPlastic: OFFTags.isPlastic(material),
                             recyclable: item["recycling"]?.string.flatMap(OFFTags.isRecyclable))
    }
}

/// Helpers for OFF taxonomy tags such as "en:pet-1-polyethylene-terephthalate".
enum OFFTags {
    static func strip(_ tag: String) -> String {
        let parts = repairingMojibake(tag).split(separator: ":", maxSplits: 1)
        let value = parts.count == 2 && parts[0].count <= 3 ? String(parts[1]) : tag
        return value.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Some OFF tags are UTF-8 that was decoded as Latin-1 ("PlÃ¡stico"); re-decode those.
    static func repairingMojibake(_ text: String) -> String {
        guard text.contains("Ã") || text.contains("Â") else { return text }
        let scalars = text.unicodeScalars
        guard scalars.allSatisfy({ $0.value < 256 }) else { return text }
        let bytes = scalars.map { UInt8($0.value) }
        return String(validating: bytes, as: UTF8.self) ?? text
    }

    static let plasticMarkers = ["plastic", "plást", "plast", "polyethylene", "polypropylene", "polystyrene",
                                 "pet-1", "hdpe", "ldpe", "pp-5", "ps-6", "pvc", "o-7", "polyester", "nylon"]

    static func isPlastic(_ material: String) -> Bool {
        let key = material.lowercased()
        return key == "pet" || key == "pe" || key == "pp" || key == "ps" || plasticMarkers.contains { key.contains($0) }
    }

    /// `en:recycle…` → true, `en:discard` / `en:non-recyclable` → false, anything else unknown.
    static func isRecyclable(_ tag: String) -> Bool? {
        let key = strip(tag)
        if key.hasPrefix("recycle") || key.hasPrefix("return") || key == "reuse" { return true }
        if key.hasPrefix("discard") || key.contains("non-recyclable") || key == "landfill" { return false }
        return nil
    }
}
