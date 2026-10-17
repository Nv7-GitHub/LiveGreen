import Foundation

/// T1 appliance/electronics lookup (spec §5.4: ENERGY STAR Socrata datasets by brand + model).
public protocol ApplianceDatabase: Sendable {
    /// Returns nil when no certified record matches.
    func appliance(brand: String, model: String) async throws -> ApplianceRecord?
}

/// Power figures from an ENERGY STAR record.
public struct ApplianceRecord: Codable, Sendable, Hashable {
    public var brand: String
    public var model: String
    /// e.g. "Televisions", "Monitors".
    public var productType: String
    public var onModeWatts: Double?
    public var standbyWatts: Double?
    public var annualKWh: Double?
    public var datasetName: String
    public var sourceURL: URL

    public init(brand: String, model: String, productType: String, onModeWatts: Double? = nil,
                standbyWatts: Double? = nil, annualKWh: Double? = nil, datasetName: String, sourceURL: URL) {
        self.brand = brand
        self.model = model
        self.productType = productType
        self.onModeWatts = onModeWatts
        self.standbyWatts = standbyWatts
        self.annualKWh = annualKWh
        self.datasetName = datasetName
        self.sourceURL = sourceURL
    }
}
