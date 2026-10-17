import Foundation
import GreenCore

/// Demo T1 resolver: answers from a `ProductDatabase` (GTIN) and an `ApplianceDatabase` (brand + model).
/// Used by demo mode so fixture scans show mixed tiers; the real Open Food Facts / ENERGY STAR
/// resolvers replace it in live mode.
public struct FakeRecordResolver: MetricResolver {
    public let tier = Tier.exactRecord
    public let name = "Demo records"
    public var products: any ProductDatabase
    public var appliances: any ApplianceDatabase

    public init(products: any ProductDatabase = FakeProductDatabase(), appliances: any ApplianceDatabase = FakeApplianceDatabase()) {
        self.products = products
        self.appliances = appliances
    }

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let ids = request.component.identifiers
        if let gtin = ids.gtin, let record = try await products.product(gtin: gtin),
           let perKg = record.carbonKgPerKg, let mass = record.netMassKg ?? request.component.quantities.massKg {
            let source = Source(title: "Open Food Facts: \(record.name)", url: record.sourceURL, tier: .exactRecord)
            var metrics: [MetricKey: Measured] = [:]
            if request.metrics.contains(.carbon) {
                metrics[.carbon] = Measured(value: perKg * mass, relativeRange: 0.05, unit: .kgCO2e, tier: .exactRecord, sources: [source])
            }
            return ResolverOutput(metrics: metrics, stageShares: record.stageShares)
        }
        if let brand = ids.brand, let model = ids.model, let record = try await appliances.appliance(brand: brand, model: model) {
            let source = Source(title: "\(record.datasetName): \(record.brand) \(record.model)", url: record.sourceURL, tier: .exactRecord)
            var metrics: [MetricKey: Measured] = [:]
            let pairs: [(MetricKey, Double?)] = [(.powerOn, record.onModeWatts), (.standbyPower, record.standbyWatts),
                                                 (.yearlyElectricity, record.annualKWh)]
            for case let (metric, value?) in pairs where request.metrics.contains(metric) {
                metrics[metric] = .exact(value, unit: metric.unit, tier: .exactRecord, sources: [source])
            }
            return ResolverOutput(metrics: metrics)
        }
        return .empty
    }
}
