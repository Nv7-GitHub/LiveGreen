import Foundation

extension ProductRecord {
    /// Agribalyse figures are category-level LCA data matched to the product, so they carry ±20%.
    static let carbonRelativeRange = 0.2

    public var recordSource: Source {
        Source(title: "Open Food Facts: \(name)", url: sourceURL, tier: .exactRecord)
    }

    /// T1 metrics for one item of `massKg` (defaults to the product's net quantity).
    /// Only metrics the record actually supports are returned.
    public func measuredMetrics(massKg: Double? = nil) -> [MetricKey: Measured] {
        var metrics: [MetricKey: Measured] = [:]
        if let perKg = carbonKgPerKg, let mass = massKg ?? netMassKg, mass > 0 {
            let source = Source(title: "Open Food Facts / Agribalyse: \(name)", url: sourceURL, tier: .exactRecord,
                                quote: "co2_total \(perKg) kg CO2e per kg")
            metrics[.carbon] = Measured(value: perKg * mass, relativeRange: Self.carbonRelativeRange,
                                        unit: .kgCO2e, tier: .exactRecord, sources: [source])
        }
        if let plastic = plasticMassG {
            metrics[.plasticMass] = .exact(plastic, unit: .grams, tier: .exactRecord, sources: [packagingSource])
        }
        if let recyclable = recyclablePackagingPercent {
            metrics[.recyclablePercent] = .exact(recyclable, unit: .percent, tier: .exactRecord, sources: [packagingSource])
        }
        return metrics
    }

    /// Grams of plastic packaging; nil unless every plastic part has a weight.
    public var plasticMassG: Double? {
        guard !packaging.isEmpty else { return nil }
        let plastic = packaging.filter(\.isPlastic)
        guard plastic.allSatisfy({ $0.massG != nil }) else { return nil }
        if plastic.isEmpty { return packaging.contains { $0.massG != nil } ? 0 : nil }
        return plastic.compactMap(\.massG).reduce(0, +)
    }

    /// Mass-weighted share of packaging marked recyclable; nil unless every part has weight and status.
    public var recyclablePackagingPercent: Double? {
        let parts = packaging.compactMap { part in part.massG.flatMap { mass in part.recyclable.map { (mass, $0) } } }
        guard !packaging.isEmpty, parts.count == packaging.count else { return nil }
        let total = parts.map(\.0).reduce(0, +)
        guard total > 0 else { return nil }
        return 100 * parts.filter(\.1).map(\.0).reduce(0, +) / total
    }

    private var packagingSource: Source {
        Source(title: "Open Food Facts packaging: \(name)", url: sourceURL, tier: .exactRecord)
    }
}
