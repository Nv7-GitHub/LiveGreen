import Foundation

/// T1 packaged-goods lookup by GTIN (spec §5.4: Open Food Facts).
public protocol ProductDatabase: Sendable {
    /// Returns nil when the GTIN is unknown.
    func product(gtin: String) async throws -> ProductRecord?
}

/// The fields LiveGreen uses from an Open Food Facts product.
public struct ProductRecord: Codable, Sendable, Hashable {
    public var gtin: String
    public var name: String
    public var brand: String?
    public var category: Category
    /// Net quantity of the product, kg.
    public var netMassKg: Double?
    /// `ecoscore_data.agribalyse.co2_total`, kg CO2e per kg of product.
    public var carbonKgPerKg: Double?
    /// Agribalyse per-stage split as fractions of the total.
    public var stageShares: [LifecycleStage: Double]
    public var packaging: [PackagingPart]
    public var sourceURL: URL

    public init(gtin: String, name: String, brand: String? = nil, category: Category, netMassKg: Double? = nil,
                carbonKgPerKg: Double? = nil, stageShares: [LifecycleStage: Double] = [:],
                packaging: [PackagingPart] = [], sourceURL: URL) {
        self.gtin = gtin
        self.name = name
        self.brand = brand
        self.category = category
        self.netMassKg = netMassKg
        self.carbonKgPerKg = carbonKgPerKg
        self.stageShares = stageShares
        self.packaging = packaging
        self.sourceURL = sourceURL
    }
}

/// One packaging element.
public struct PackagingPart: Codable, Sendable, Hashable {
    public var material: String
    public var massG: Double?
    public var isPlastic: Bool
    public var recyclable: Bool?

    public init(material: String, massG: Double? = nil, isPlastic: Bool, recyclable: Bool? = nil) {
        self.material = material
        self.massG = massG
        self.isPlastic = isPlastic
        self.recyclable = recyclable
    }
}
