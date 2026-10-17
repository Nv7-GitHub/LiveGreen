/// T2: cited spec-sheet values researched on the web (spec §5.4). Only components with a brand and model
/// are researched, and at most `maxConcurrent` research calls run at once across the scan (spec §11).
public struct SpecResearchResolver: MetricResolver {
    public let tier = Tier.researchedSpec
    public let name = "Spec research"
    public let researcher: any SpecResearcher
    let limiter: ConcurrencyLimiter

    public init(researcher: any SpecResearcher, maxConcurrent: Int = 4) {
        self.researcher = researcher
        self.limiter = ConcurrencyLimiter(limit: maxConcurrent)
    }

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let component = request.component
        guard let brand = component.identifiers.brand, !brand.isEmpty,
              let model = component.identifiers.model, !model.isEmpty, !request.metrics.isEmpty else { return .empty }
        let metrics = request.metrics.sorted { $0.rawValue < $1.rawValue }
        let spec = try await limiter.run {
            try await researcher.research(name: component.name, category: component.category,
                                          identifiers: component.identifiers, metrics: metrics)
        }
        return ResolverOutput(metrics: spec.measured.filter { request.metrics.contains($0.key) })
    }
}

/// A counting semaphore for async work.
actor ConcurrencyLimiter {
    let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// For tests: the number of slots in use.
    var inFlight: Int { running }
}
