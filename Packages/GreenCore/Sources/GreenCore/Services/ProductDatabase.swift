import Foundation

/// T1 packaged-goods lookup by GTIN (spec §5.4: Open Food Facts), and by brand and name for food without one.
public protocol ProductDatabase: Sendable {
    /// Returns nil when the GTIN is unknown.
    func product(gtin: String) async throws -> ProductRecord?
    /// The record a brand and product name confidently stand for, with a carbon figure (`ProductNameMatch`), or
    /// nil when no record matches well enough.
    func searchProduct(brand: String, name: String) async throws -> ProductRecord?
    /// The record's front-of-pack photo, or nil when it has none or the download fails.
    func productImage(for record: ProductRecord) async -> Data?
}

extension ProductDatabase {
    public func searchProduct(brand: String, name: String) async throws -> ProductRecord? { nil }
    public func productImage(for record: ProductRecord) async -> Data? { nil }
}

/// The fields LiveGreen uses from an Open Food Facts product.
public struct ProductRecord: Codable, Sendable, Hashable {
    public var gtin: String
    public var name: String
    public var brand: String?
    public var category: Category
    /// Net quantity of the product, kg.
    public var netMassKg: Double?
    /// The label's serving size, kg, when the record has one.
    public var servingKg: Double?
    /// `ecoscore_data.agribalyse.co2_total`, kg CO2e per kg of product.
    public var carbonKgPerKg: Double?
    /// Agribalyse per-stage split as fractions of the total.
    public var stageShares: [LifecycleStage: Double]
    public var packaging: [PackagingPart]
    public var sourceURL: URL
    /// Reference food-group key inferred from the record's categories (e.g. "bottled_water").
    public var foodGroup: String?
    /// Front-of-pack photo.
    public var imageURL: URL?

    public init(gtin: String, name: String, brand: String? = nil, category: Category, netMassKg: Double? = nil,
                servingKg: Double? = nil, carbonKgPerKg: Double? = nil, stageShares: [LifecycleStage: Double] = [:],
                packaging: [PackagingPart] = [], sourceURL: URL, foodGroup: String? = nil, imageURL: URL? = nil) {
        self.gtin = gtin
        self.name = name
        self.brand = brand
        self.category = category
        self.netMassKg = netMassKg
        self.servingKg = servingKg
        self.carbonKgPerKg = carbonKgPerKg
        self.stageShares = stageShares
        self.packaging = packaging
        self.sourceURL = sourceURL
        self.foodGroup = foodGroup
        self.imageURL = imageURL
    }

    /// True when the record carries footprint data of its own. A bare name-only record (common for
    /// US products) needs identification to fill in what the item is made of and how big it is.
    public var hasFootprintData: Bool {
        carbonKgPerKg != nil || !packaging.isEmpty
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
