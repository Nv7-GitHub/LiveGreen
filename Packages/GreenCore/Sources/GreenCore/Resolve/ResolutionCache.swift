/// What the evidence ladder resolved for one identifier, so rescans give identical numbers (spec §5.4).
public struct CachedResolution: Codable, Sendable, Hashable {
    public var metrics: [MetricKey: Measured]
    public var stageShares: [LifecycleStage: Double]
    public var plasticPackagingShare: Double?
    /// The category the metrics were resolved for; nil in entries saved by older builds.
    public var category: Category?

    public init(metrics: [MetricKey: Measured], stageShares: [LifecycleStage: Double] = [:],
                plasticPackagingShare: Double? = nil, category: Category? = nil) {
        self.metrics = metrics
        self.stageShares = stageShares
        self.plasticPackagingShare = plasticPackagingShare
        self.category = category
    }
}

/// Resolution cache keyed by `Component.resolutionKey` (GTIN, brand|model, sized brand|model line or generic item
/// kind). The app backs it with SwiftData.
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
