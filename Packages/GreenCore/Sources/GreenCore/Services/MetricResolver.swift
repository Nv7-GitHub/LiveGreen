/// One tier of the evidence ladder (spec §5.4). The ladder asks resolvers in tier order for the
/// still-missing metrics; each returns what it can. A thrown error drops that resolver only.
public protocol MetricResolver: Sendable {
    var tier: Tier { get }
    /// Short name for logs and warnings, e.g. "Open Food Facts".
    var name: String { get }
    /// Returns values for any subset of `request.metrics`; an empty map means "nothing here".
    func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput
}

/// What a resolver is asked for.
public struct ResolutionRequest: Sendable, Hashable {
    public var component: Component
    public var metrics: Set<MetricKey>
    public var profile: UserProfile

    public init(component: Component, metrics: Set<MetricKey>, profile: UserProfile) {
        self.component = component
        self.metrics = metrics
        self.profile = profile
    }
}

/// Resolver result: metric values plus optional lifecycle-stage split for the flow view and, with a
/// plastic value, the share of it that is packaging (spec §4 item + packaging split).
public struct ResolverOutput: Sendable, Hashable {
    public var metrics: [MetricKey: Measured]
    public var stageShares: [LifecycleStage: Double]
    public var plasticPackagingShare: Double?

    public init(metrics: [MetricKey: Measured] = [:], stageShares: [LifecycleStage: Double] = [:],
                plasticPackagingShare: Double? = nil) {
        self.metrics = metrics
        self.stageShares = stageShares
        self.plasticPackagingShare = plasticPackagingShare
    }

    public static let empty = ResolverOutput()
}
