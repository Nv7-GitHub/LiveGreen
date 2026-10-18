/// Simple additive totals across components: values and range bounds are summed, tier is the weakest.
/// The Monte Carlo `ImpactEngine` (spec §5.6) supersedes this for uncertainty-aware totals.
public enum ScanTotals {
    /// Metrics that are meaningful to add across components.
    public static let additiveMetrics: [MetricKey] = [.carbon, .water, .land, .yearlyElectricity, .plasticMass, .waterPollution]

    public static func sum(_ components: [Component]) -> [MetricKey: Measured] {
        var totals: [MetricKey: Measured] = [:]
        for metric in additiveMetrics {
            let values = components.compactMap { $0.metrics[metric] }
            guard !values.isEmpty else { continue }
            // One item's total is that item's own figure, sources included.
            if values.count == 1 { totals[metric] = values[0]; continue }
            totals[metric] = Measured(
                value: values.reduce(0) { $0 + $1.value },
                low: values.reduce(0) { $0 + $1.low },
                high: values.reduce(0) { $0 + $1.high },
                unit: metric.unit,
                tier: values.map(\.tier).max() ?? .estimate,
                sources: [])
        }
        return totals
    }
}
