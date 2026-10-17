/// T4: turns the identify call's fallback estimates into `Measured` values with a range of at least ±50%.
public struct EstimateResolver: MetricResolver {
    public let tier = Tier.estimate
    public let name = "Model estimate"

    public init() {}

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        var metrics: [MetricKey: Measured] = [:]
        for (metric, estimate) in request.component.fallbackEstimates where request.metrics.contains(metric) {
            let minDelta = abs(estimate.value) * 0.5
            let source = Source(title: "Claude estimate (no record found)", tier: .estimate)
            metrics[metric] = Measured(
                value: estimate.value,
                low: min(estimate.low, estimate.value - minDelta),
                high: max(estimate.high, estimate.value + minDelta),
                unit: metric.unit, tier: .estimate, sources: [source])
        }
        return ResolverOutput(metrics: metrics)
    }
}
