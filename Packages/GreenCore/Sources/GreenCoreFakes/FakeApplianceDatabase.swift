import Foundation
import GreenCore

/// In-memory `brand|model` (lowercased) → appliance table.
public struct FakeApplianceDatabase: ApplianceDatabase {
    public var records: [String: ApplianceRecord]

    public init(records: [String: ApplianceRecord] = FakeApplianceDatabase.defaultRecords) {
        self.records = records
    }

    public func appliance(brand: String, model: String) async throws -> ApplianceRecord? {
        records["\(brand.lowercased())|\(model.lowercased())"]
    }

    public static let defaultRecords: [String: ApplianceRecord] = [
        "dell|s2721h": ApplianceRecord(
            brand: "Dell", model: "S2721H", productType: "Monitors", onModeWatts: 16.6, standbyWatts: 0.3,
            annualKWh: 52.4, datasetName: "ENERGY STAR Certified Displays",
            sourceURL: URL(string: "https://data.energystar.gov/Active-Specifications/ENERGY-STAR-Certified-Displays/xsyb-v8gb")!),
    ]
}
