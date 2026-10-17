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

    public init(gtin: String? = nil, brand: String? = nil, model: String? = nil,
                materials: [MaterialShare] = [], ocrText: String? = nil) {
        self.gtin = gtin
        self.brand = brand
        self.model = model
        self.materials = materials
        self.ocrText = ocrText
    }

    /// Cache key: the GTIN, else `brand|model` lowercased; nil when neither is known (spec §5.4).
    public var cacheKey: String? {
        if let gtin, !gtin.isEmpty { return "gtin:\(gtin)" }
        guard let brand, let model, !brand.isEmpty, !model.isEmpty else { return nil }
        return "bm:\(brand.lowercased())|\(model.lowercased())"
    }
}
