import Foundation

/// The user's annualized footprint for the categories they have scanned (spec §9).
public struct ScannedFootprint: Sendable, Hashable {
    /// Yearly totals per metric, canonical units.
    public var yearly: [MetricKey: Double]
    /// Yearly totals per category and metric.
    public var byCategory: [Category: [MetricKey: Double]]

    public init(byCategory: [Category: [MetricKey: Double]]) {
        self.byCategory = byCategory
        yearly = byCategory.values.reduce(into: [:]) { totals, metrics in
            for (metric, value) in metrics { totals[metric, default: 0] += value }
        }
    }

    public static let empty = ScannedFootprint(byCategory: [:])

    /// Scanned categories that contribute to a metric.
    public func categories(for metric: MetricKey) -> Set<Category> {
        Set(byCategory.filter { $0.value[metric] != nil }.keys)
    }

    /// Sums yearly impacts of every scanned component. The same item scanned twice (same GTIN or
    /// brand|model, else same category and name) counts once, using the latest scan.
    public static func from(scans: [ScanResult], engine: ImpactEngine = ImpactEngine()) -> ScannedFootprint {
        var latest: [String: (component: Component, seed: UInt64)] = [:]
        for scan in scans.sorted(by: { $0.date < $1.date }) {
            for component in scan.components {
                let key = component.identifiers.cacheKey ?? "\(component.category.rawValue)|\(component.name.lowercased())"
                latest[key] = (component, scan.seed)
            }
        }
        var byCategory: [Category: [MetricKey: Double]] = [:]
        for (component, seed) in latest.values {
            for (metric, yearly) in engine.annualized(component, seed: seed) where CohortModel.comparedMetrics.contains(metric) {
                byCategory[component.category, default: [:]][metric, default: 0] += yearly.value
            }
        }
        return ScannedFootprint(byCategory: byCategory)
    }
}

/// A point on the percentile trend sparkline.
public struct PercentilePoint: Sendable, Hashable {
    public var date: Date
    public var greenerThan: Double
}

public enum Percentiles {
    /// Share of the distribution above `value`: 1 − CDF(value).
    public static func greenerThan(_ value: Double, in distribution: LogNormal) -> Double {
        1 - distribution.cdf(value)
    }

    /// Percentile after each scan, recomputed over all scans up to that date.
    public static func trend(scans: [ScanResult], model: CohortModel, metric: MetricKey = .carbon,
                             engine: ImpactEngine = ImpactEngine()) -> [PercentilePoint] {
        let ordered = scans.sorted { $0.date < $1.date }
        return ordered.indices.compactMap { index in
            let footprint = ScannedFootprint.from(scans: Array(ordered[...index]), engine: engine)
            guard let comparison = model.compare(footprint).first(where: { $0.metric == metric }) else { return nil }
            return PercentilePoint(date: ordered[index].date, greenerThan: comparison.greenerThan)
        }
    }
}
