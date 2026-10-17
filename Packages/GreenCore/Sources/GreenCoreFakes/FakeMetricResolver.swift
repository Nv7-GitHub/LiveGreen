import GreenCore

/// A resolver at any tier backed by a closure; handy for ladder tests and previews.
public struct FakeMetricResolver: MetricResolver {
    public let tier: Tier
    public let name: String
    private let handler: @Sendable (ResolutionRequest) throws -> ResolverOutput

    public init(tier: Tier, name: String = "Fake", handler: @escaping @Sendable (ResolutionRequest) throws -> ResolverOutput) {
        self.tier = tier
        self.name = name
        self.handler = handler
    }

    /// Returns fixed values (filtered to the requested metrics) for every component.
    public init(tier: Tier, name: String = "Fake", values: [MetricKey: Double]) {
        self.init(tier: tier, name: name) { request in
            var out: [MetricKey: Measured] = [:]
            for (metric, value) in values where request.metrics.contains(metric) {
                out[metric] = Measured(value: value, relativeRange: 0.1, unit: metric.unit, tier: tier,
                                       sources: [Source(title: name, tier: tier)])
            }
            return ResolverOutput(metrics: out)
        }
    }

    /// Always throws, to exercise fallthrough.
    public static func failing(tier: Tier, name: String = "Failing") -> FakeMetricResolver {
        FakeMetricResolver(tier: tier, name: name) { _ in throw GreenCoreError.timeout }
    }

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        try handler(request)
    }
}
