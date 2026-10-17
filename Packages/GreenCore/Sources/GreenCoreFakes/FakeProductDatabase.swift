import Foundation
import GreenCore

/// In-memory GTIN → product table.
public struct FakeProductDatabase: ProductDatabase {
    public var records: [String: ProductRecord]

    public init(records: [String: ProductRecord] = FakeProductDatabase.defaultRecords) {
        self.records = records
    }

    public func product(gtin: String) async throws -> ProductRecord? {
        records[gtin]
    }

    public static let defaultRecords: [String: ProductRecord] = [
        "5449000000996": ProductRecord(
            gtin: "5449000000996", name: "Coca-Cola Original Taste 330 ml", brand: "Coca-Cola", category: .food,
            netMassKg: 0.33, carbonKgPerKg: 0.47,
            stageShares: [.materials: 0.18, .manufacturing: 0.12, .transport: 0.10, .use: 0.02, .endOfLife: 0.58],
            packaging: [PackagingPart(material: "aluminium", massG: 13, isPlastic: false, recyclable: true)],
            sourceURL: URL(string: "https://world.openfoodfacts.org/product/5449000000996")!),
    ]
}
