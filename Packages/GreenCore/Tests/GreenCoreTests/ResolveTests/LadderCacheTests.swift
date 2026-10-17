import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Evidence ladder cache and tiers")
struct LadderCacheTests {
    let monitor = Component(name: "Monitor", category: .electronic, identifiers: Identifiers(brand: "Dell", model: "S2721H"),
                            fallbackEstimates: [.carbon: EstimateRange(value: 400, low: 300, high: 500)])

    @Test func cacheHitSkipsResolvers() async {
        let counter = CallCounter()
        let resolver = FakeMetricResolver(tier: .factorModel) { request in
            counter.increment()
            return ResolverOutput(metrics: [.powerOn: Measured(value: 20, relativeRange: 0.1, unit: .watts, tier: .factorModel)])
        }
        let cache = InMemoryResolutionCache()
        let ladder = EvidenceLadder(resolvers: [resolver, EstimateResolver()], cache: cache)

        let first = await ladder.resolve(monitor, profile: .default)
        #expect(counter.value == 1)
        #expect(await cache.count == 1)

        var rescan = Component(name: "Dell monitor", category: .electronic, identifiers: monitor.identifiers)
        rescan.fallbackEstimates = [.carbon: EstimateRange(value: 900, low: 800, high: 1000)]
        let second = await ladder.resolve(rescan, profile: .default)
        #expect(counter.value == 1)
        #expect(second.metrics == first.metrics)
    }

    @Test func componentsWithoutIdentifiersAreNotCached() async {
        let cache = InMemoryResolutionCache()
        let ladder = EvidenceLadder(resolvers: [EstimateResolver()], cache: cache)
        _ = await ladder.resolve(Component(name: "Lamp", category: .electronic,
                                           fallbackEstimates: [.carbon: EstimateRange(value: 5, low: 4, high: 6)]),
                                 profile: .default)
        #expect(await cache.count == 0)
    }

    @Test func genericItemsAreCachedByKindAndKeepTheCachedCategory() async {
        let cache = InMemoryResolutionCache()
        let ladder = EvidenceLadder(resolvers: [FactorModelResolver(), EstimateResolver()], cache: cache)
        let tote = Component(name: "Green tote bag", category: .clothing,
                             identifiers: Identifiers(materials: [MaterialShare(material: "cotton", percent: 100)],
                                                      genericKey: "tote bag"),
                             quantities: Quantities(massKg: 0.2))
        let first = await ladder.resolve(tote, profile: .default)
        #expect(await cache.count == 1)

        let rescan = Component(name: "Red tote bag", category: .household,
                               identifiers: Identifiers(genericKey: "tote bag"), quantities: Quantities(massKg: 0.5),
                               fallbackEstimates: [.carbon: EstimateRange(value: 9, low: 5, high: 14)])
        let second = await ladder.resolve(rescan, profile: .default)
        #expect(second.category == .clothing)
        #expect(second.metrics == first.metrics)
    }

    @Test func tierFilterRunsOnlyThatPhase() async {
        let ladder = EvidenceLadder(resolvers: [
            FakeMetricResolver(tier: .exactRecord, values: [.powerOn: 18]),
            FakeMetricResolver(tier: .factorModel, values: [.lifespan: 6]),
            EstimateResolver(),
        ])
        let records = await ladder.resolve(monitor, profile: .default, tiers: .exactRecord ... .exactRecord)
        #expect(records.metrics.keys.sorted { $0.rawValue < $1.rawValue } == [.powerOn])
        let rest = await ladder.resolve(records, profile: .default, tiers: .factorModel ... .estimate)
        #expect(rest.metrics[.powerOn]?.tier == .exactRecord)
        #expect(rest.metrics[.lifespan]?.tier == .factorModel)
        #expect(rest.metrics[.carbon]?.tier == .estimate)
    }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}
