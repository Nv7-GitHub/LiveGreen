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

    /// The demo monitor's record has no on-mode figure, so its power comes from spec research (T2) while
    /// standby and annual energy stay T1: one component, mixed tiers.
    public static let defaultRecords: [String: ApplianceRecord] = [
        "dell|s2721h": ApplianceRecord(
            brand: "Dell", model: "S2721H", productType: "Monitors", standbyWatts: 0.3,
            annualKWh: 52.4, datasetName: "ENERGY STAR Certified Displays",
            sourceURL: URL(string: "https://data.energystar.gov/Active-Specifications/ENERGY-STAR-Certified-Displays/xsyb-v8gb")!),
    ]
}
