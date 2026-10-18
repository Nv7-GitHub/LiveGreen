/// T4: turns the identify call's fallback estimates into `Measured` values with a range of at least ±50%.
/// The AI estimates food per serving, so a per-pack item's amounts are scaled up to the whole pack.
public struct EstimateResolver: MetricResolver {
    public let tier = Tier.estimate
    public let name = "Model estimate"

    public init() {}

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        var metrics: [MetricKey: Measured] = [:]
        let servings = FoodServing.servingsPerPack(request.component)
        for (metric, perServing) in request.component.fallbackEstimates where request.metrics.contains(metric) {
            let scale = FoodServing.massScaledMetrics.contains(metric) ? servings : 1
            let estimate = EstimateRange(value: perServing.value * scale, low: perServing.low * scale,
                                         high: perServing.high * scale)
            let minDelta = abs(estimate.value) * 0.5
            let source = Source(title: scale == 1 ? "AI estimate from the photo (no record found)"
                                                  : "AI estimate per serving × \(Self.servingsText(scale)) servings in the pack",
                                tier: .estimate)
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

    /// "11" or "2.5": the servings in a pack, as the source note shows them.
    static func servingsText(_ servings: Double) -> String {
        servings >= 10 ? String(Int(servings.rounded())) : String(format: "%.1f", servings)
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
