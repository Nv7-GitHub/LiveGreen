/// Runs resolvers in tier order per component, stopping per metric at the first value (spec §5.4).
/// Values from different tiers are kept per metric, so one component can mix tiers.
public struct EvidenceLadder: Sendable {
    public let resolvers: [any MetricResolver]

    /// Resolvers are sorted by tier; ties keep the given order.
    public init(resolvers: [any MetricResolver]) {
        self.resolvers = resolvers.enumerated()
            .sorted { ($0.element.tier, $0.offset) < ($1.element.tier, $1.offset) }
            .map(\.element)
    }

    /// Reports each resolved metric and each failed resolver as it happens.
    public enum Progress: Sendable {
        case resolved(MetricKey, Tier)
        case resolverFailed(name: String, error: any Error)
    }

    /// Fills the component's missing applicable metrics; existing metrics are kept.
    public func resolve(_ component: Component, profile: UserProfile,
                        progress: @Sendable (Progress) -> Void = { _ in }) async -> Component {
        var result = component
        for resolver in resolvers {
            let missing = Set(result.missingMetrics)
            if missing.isEmpty { break }
            let request = ResolutionRequest(component: result, metrics: missing, profile: profile)
            do {
                let output = try await resolver.resolve(request)
                for (metric, measured) in output.metrics where missing.contains(metric) {
                    result.metrics[metric] = measured
                    progress(.resolved(metric, measured.tier))
                }
                if result.stageShares.isEmpty, !output.stageShares.isEmpty {
                    result.stageShares = output.stageShares
                }
            } catch {
                progress(.resolverFailed(name: resolver.name, error: error))
            }
        }
        return result
    }
}
