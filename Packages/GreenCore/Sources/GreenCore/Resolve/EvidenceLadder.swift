/// Runs resolvers in tier order per component, stopping per metric at the first value (spec §5.4).
/// Values from different tiers are kept per metric, so one component can mix tiers. With a cache, a
/// component whose GTIN or brand|model was resolved before skips the resolvers entirely.
public struct EvidenceLadder: Sendable {
    public let resolvers: [any MetricResolver]
    public let cache: (any ResolutionCache)?

    public static let allTiers: ClosedRange<Tier> = .exactRecord ... .estimate

    /// Resolvers are sorted by tier; ties keep the given order.
    public init(resolvers: [any MetricResolver], cache: (any ResolutionCache)? = nil) {
        self.resolvers = resolvers.enumerated()
            .sorted { ($0.element.tier, $0.offset) < ($1.element.tier, $1.offset) }
            .map(\.element)
        self.cache = cache
    }

    /// Reports each resolved metric and each failed resolver as it happens.
    public enum Progress: Sendable {
        case resolved(MetricKey, Tier)
        case resolverFailed(name: String, error: any Error)
    }

    /// Cache-first resolution through every tier; the result is remembered for next time.
    public func resolve(_ component: Component, profile: UserProfile,
                        progress: @Sendable (Progress) -> Void = { _ in }) async -> Component {
        if let hit = await cached(component) { return hit }
        let resolved = await resolve(component, profile: profile, tiers: Self.allTiers, progress: progress)
        await remember(resolved)
        return resolved
    }

    /// Fills the component's missing applicable metrics using only resolvers in `tiers`; existing
    /// metrics are kept and the cache is not consulted (the scan pipeline runs one phase per tier).
    public func resolve(_ component: Component, profile: UserProfile, tiers: ClosedRange<Tier>,
                        progress: @Sendable (Progress) -> Void = { _ in }) async -> Component {
        var result = component
        for resolver in resolvers where tiers.contains(resolver.tier) {
            let missing = Set(result.missingMetrics)
            if missing.isEmpty { break }
            let request = ResolutionRequest(component: result, metrics: missing, profile: profile)
            do {
                let output = try await resolver.resolve(request)
                for (metric, measured) in output.metrics where missing.contains(metric) {
                    result.metrics[metric] = measured
                    progress(.resolved(metric, measured.tier))
                }
                if missing.contains(.plasticMass), output.metrics[.plasticMass] != nil {
                    result.plasticPackagingShare = output.plasticPackagingShare
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

    /// The component with its cached metrics and stage split, or nil on a miss.
    public func cached(_ component: Component) async -> Component? {
        guard let cache, let key = component.identifiers.cacheKey,
              let hit = await cache.cachedResolution(forKey: key) else { return nil }
        var result = component
        result.metrics.merge(hit.metrics) { _, cached in cached }
        if !hit.stageShares.isEmpty { result.stageShares = hit.stageShares }
        if let share = hit.plasticPackagingShare { result.plasticPackagingShare = share }
        return result
    }

    /// Stores a resolved component under its identifier key (no-op without a key or metrics).
    public func remember(_ component: Component) async {
        guard let cache, let key = component.identifiers.cacheKey, !component.metrics.isEmpty else { return }
        await cache.store(CachedResolution(metrics: component.metrics, stageShares: component.stageShares,
                                           plasticPackagingShare: component.plasticPackagingShare), forKey: key)
    }
}
