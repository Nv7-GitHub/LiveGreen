/// What the evidence ladder resolved for one identifier, so rescans give identical numbers (spec §5.4).
public struct CachedResolution: Codable, Sendable, Hashable {
    public var metrics: [MetricKey: Measured]
    public var stageShares: [LifecycleStage: Double]

    public init(metrics: [MetricKey: Measured], stageShares: [LifecycleStage: Double] = [:]) {
        self.metrics = metrics
        self.stageShares = stageShares
    }
}

/// Resolution cache keyed by `Identifiers.cacheKey` (GTIN or brand|model). The app backs it with SwiftData.
public protocol ResolutionCache: Sendable {
    func cachedResolution(forKey key: String) async -> CachedResolution?
    func store(_ resolution: CachedResolution, forKey key: String) async
}

/// Process-lifetime cache for tests and previews.
public actor InMemoryResolutionCache: ResolutionCache {
    private var entries: [String: CachedResolution] = [:]

    public init() {}

    public func cachedResolution(forKey key: String) -> CachedResolution? { entries[key] }

    public func store(_ resolution: CachedResolution, forKey key: String) { entries[key] = resolution }

    public var count: Int { entries.count }
}
