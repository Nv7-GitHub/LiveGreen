/// T4: turns the identify call's fallback estimates into `Measured` values with a range of at least ±50%.
public struct EstimateResolver: MetricResolver {
    public let tier = Tier.estimate
    public let name = "Model estimate"

    public init() {}

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        var metrics: [MetricKey: Measured] = [:]
        for (metric, estimate) in request.component.fallbackEstimates where request.metrics.contains(metric) {
            let minDelta = abs(estimate.value) * 0.5
            let source = Source(title: "AI estimate from the photo (no record found)", tier: .estimate)
            var low = min(estimate.low, estimate.value - minDelta)
            var high = max(estimate.high, estimate.value + minDelta)
            var value = estimate.value
            if let bounds = Self.bounds(for: metric.unit) {
                value = min(max(value, bounds.lowerBound), bounds.upperBound)
                low = min(max(low, bounds.lowerBound), value)
                high = max(min(high, bounds.upperBound), value)
            } else {
                low = max(low, 0)
            }
            metrics[metric] = Measured(value: value, low: low, high: high, unit: metric.unit, tier: .estimate,
                                       sources: [source])
        }
        return ResolverOutput(metrics: metrics)
    }

    /// Bounded scales: a percentage or a 0–10 score cannot be widened past its ends.
    static func bounds(for unit: MetricUnit) -> ClosedRange<Double>? {
        switch unit {
        case .percent: 0...100
        case .score10: 0...10
        default: nil
        }
    }
}
