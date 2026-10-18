import Foundation

/// The user's annualized footprint for the categories they have scanned (spec §9).
public struct ScannedFootprint: Sendable, Hashable {
    /// Yearly totals per metric, canonical units.
    public var yearly: [MetricKey: Double]
    /// Yearly totals per category and metric.
    public var byCategory: [Category: [MetricKey: Double]]
    /// Yearly kg CO2e that smart plugs' green-hours schedules avoid by moving charging to cleaner hours. The
    /// electricity is the same, so it only lowers carbon (`CohortModel.estimate`).
    public var scheduledSavingsKg: Double

    public init(byCategory: [Category: [MetricKey: Double]], scheduledSavingsKg: Double = 0) {
        self.byCategory = byCategory
        self.scheduledSavingsKg = max(scheduledSavingsKg, 0)
        yearly = byCategory.values.reduce(into: [:]) { totals, metrics in
            for (metric, value) in metrics { totals[metric, default: 0] += value }
        }
    }

    public static let empty = ScannedFootprint(byCategory: [:])

    /// Scanned categories that contribute to a metric.
    public func categories(for metric: MetricKey) -> Set<Category> {
        Set(byCategory.filter { $0.value[metric] != nil }.keys)
    }

    /// Sums yearly impacts of every scanned component. An item scanned again in a later scan (same GTIN or
    /// brand|model, else same category and name) replaces the earlier scan's count of it, so repeat scans
    /// count once while several units in one scan (two monitors on a desk) all count. Only the user's own items
    /// count (`Component.isCounted`): not a stranger's car, store stock, a background item or a post seen on screen.
    public static func from(scans: [ScanResult], scheduledSavingsKg: Double = 0,
                            engine: ImpactEngine = ImpactEngine()) -> ScannedFootprint {
        var latest: [String: [(component: Component, seed: UInt64)]] = [:]
        for scan in scans.sorted(by: { $0.date < $1.date }) {
            var units: [String: [(component: Component, seed: UInt64)]] = [:]
            for component in scan.components where component.isCounted {
                let key = component.identifiers.cacheKey ?? "\(component.category.rawValue)|\(component.name.lowercased())"
                units[key, default: []].append((component, scan.seed))
            }
            latest.merge(units) { _, newer in newer }
        }
        var byCategory: [Category: [MetricKey: Double]] = [:]
        for (component, seed) in latest.values.joined() {
            for (metric, yearly) in engine.annualized(component, seed: seed) where CohortModel.comparedMetrics.contains(metric) {
                byCategory[component.category, default: [:]][metric, default: 0] += yearly.value
            }
        }
        return ScannedFootprint(byCategory: byCategory, scheduledSavingsKg: scheduledSavingsKg)
    }
}

public enum Percentiles {
    /// Share of the distribution above `value`: 1 − CDF(value).
    public static func greenerThan(_ value: Double, in distribution: LogNormal) -> Double {
        1 - distribution.cdf(value)
    }
}
