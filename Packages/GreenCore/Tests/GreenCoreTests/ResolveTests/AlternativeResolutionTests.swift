import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// How swaps are resolved against the item they replace (S1–S5 of the image QA): on the same tier, basis and lifespan.
@Suite("Alternative resolution")
struct AlternativeResolutionTests {
    /// Returns the given swaps for every component.
    private struct StubSuggester: AlternativeSuggester {
        let swaps: [Alternative]
        func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion] {
            components.map { AlternativeSuggestion(componentID: $0.id, alternatives: swaps) }
        }
    }

    private static let store = ReferenceStore.bundled

    private func pipeline(_ swaps: [Alternative] = [], cache: (any ResolutionCache)? = nil) -> ScanPipeline {
        ScanPipeline(vision: FakeVisionIdentifier(scene: .deskSetup), alternatives: StubSuggester(swaps: swaps),
                     products: FakeProductDatabase(),
                     ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: Self.store), EstimateResolver()], cache: cache),
                     engine: ImpactEngine(reference: Self.store), profile: .default)
    }

    /// The original resolved the way a scan resolves it (factor model, then estimates).
    private func resolved(_ component: Component, in pipeline: ScanPipeline) async -> Component {
        let ladder = pipeline.ladder
        return pipeline.completed(await ladder.resolve(component, profile: .default, tiers: EvidenceLadder.allTiers),
                                  deferrable: nil)
    }

    private func swaps(for original: Component, _ swaps: [Alternative],
                       cache: (any ResolutionCache)? = nil) async throws -> (Component, [Alternative]) {
        let pipeline = pipeline(swaps, cache: cache)
        let scan = ScanResult(title: "Test", components: [await resolved(original, in: pipeline)])
        let updated = try #require(try await pipeline.suggestAlternatives(for: scan).components.first)
        return (updated, updated.alternatives)
    }

    private static func estimates(_ values: [MetricKey: Double]) -> [MetricKey: EstimateRange] {
        values.mapValues { EstimateRange(value: $0, low: $0 * 0.5, high: $0 * 1.5) }
    }

    // MARK: S2: same tier as the original

    @Test func aFoodSwapIsModeledFromItsFoodGroupNotItsEstimate() async throws {
        // 19: barley pilaf → lentil pilaf. The AI's estimate (0.25 kg, 3.5 L) made it look greener; by the factor
        // table lentils are worse on every metric, so it is not offered.
        let pilaf = Component(name: "Barley pilaf", category: .food, quantities: Quantities(servingKg: 0.25, foodGroup: "barley"),
                              usage: UsageProfile(servingsPerWeek: 2))
        let lentil = Alternative(name: "Lentil and vegetable pilaf", category: .food,
                                 quantities: Quantities(servingKg: 0.25, foodGroup: "lentils"), rationale: "",
                                 fallbackEstimates: Self.estimates([.carbon: 0.25, .water: 3.5, .land: 0.25, .waterPollution: 1]))
        let pipeline = pipeline()
        let original = await resolved(pilaf, in: pipeline)
        let swap = await pipeline.resolve(lentil, replacing: original)
        let carbon = try #require(swap.metrics[.carbon])
        #expect(carbon.tier == .factorModel)
        #expect(abs(carbon.value - 1.79 * 0.25) < 1e-6)
        #expect(try #require(swap.metrics[.water]).value > original.metrics[.water]!.value * 10)

        let (_, shown) = try await swaps(for: pilaf, [lentil])
        #expect(shown.isEmpty)
    }

    @Test func theSameFoodRelabelledIsNotOffered() async throws {
        // 27: "local seasonal broccoli" at 0.85–0.97× of the original on every metric, copied from its numbers.
        let broccoli = Component(name: "Broccoli", category: .food, quantities: Quantities(servingKg: 0.1, foodGroup: "broccoli"),
                                 usage: UsageProfile(servingsPerWeek: 2))
        let local = Alternative(name: "Local seasonal broccoli", category: .food,
                                quantities: Quantities(servingKg: 0.1, foodGroup: "brassicas"), rationale: "",
                                fallbackEstimates: Self.estimates([.carbon: 0.04, .water: 10, .land: 0.05, .waterPollution: 0.3]))
        let (_, shown) = try await swaps(for: broccoli, [local])
        #expect(shown.isEmpty)
    }

    @Test func anEfficientApplianceKeepsItsOwnPowerAndTheTablesEmbodiedCarbon() async throws {
        // 08: an inverter AC was scored on the AI's lifetime carbon (T4) against the original's factor model (T3).
        let ac = Component(name: "Window AC", category: .electronic, quantities: Quantities(deviceType: "air_conditioner"),
                           usage: UsageProfile(hoursOnPerDay: 2, standbyHoursPerDay: 22))
        let inverter = Alternative(name: "ENERGY STAR inverter window AC", category: .electronic,
                                   quantities: Quantities(ratedPowerW: 650, deviceType: "air_conditioner"),
                                   rationale: "", fallbackEstimates: Self.estimates([.powerOn: 600, .carbon: 2_870]))
        let pipeline = pipeline()
        let original = await resolved(ac, in: pipeline)
        let swap = await pipeline.resolve(inverter, replacing: original)
        #expect(swap.metrics[.powerOn]?.tier == .estimate)
        #expect(swap.metrics[.carbon]?.tier == .factorModel, "embodied carbon from the same table as the original")
        #expect(try #require(swap.metrics[.yearlyElectricity]).value < original.metrics[.yearlyElectricity]!.value)
        #expect(try #require(swap.metrics[.carbon]).value < original.metrics[.carbon]!.value)
        #expect(GreenScore.accepts(swap, replacing: original, engine: pipeline.engine))

        // A second-hand unit, or an estimate drawing more than the typical model, keeps the table's draw.
        var used = inverter
        used.condition = .used
        #expect(await pipeline.resolve(used, replacing: original).metrics[.powerOn]?.tier == .factorModel)
        var hungry = inverter
        hungry.fallbackEstimates = Self.estimates([.powerOn: 1_400])
        #expect(await pipeline.resolve(hungry, replacing: original).metrics[.powerOn] == original.metrics[.powerOn])
    }

    // MARK: S1, S3, S4: reusables

    @Test func aReusableJarIsADurableWithWashingAndIsOffered() async throws {
        // 05: the jar was tagged packaging (156 jars a year) and priced at 0.03 kg on the cups' per-use basis.
        let cup = Component(name: "PET cup", category: .packaging,
                            identifiers: Identifiers(materials: [MaterialShare(material: "pet", percent: 100)]),
                            quantities: Quantities(massKg: 0.012), usage: UsageProfile(usesPerWeek: 3))
        let jar = Alternative(name: "Reusable glass jar with lid", category: .packaging,
                              identifiers: Identifiers(materials: [MaterialShare(material: "glass", percent: 85),
                                                                   MaterialShare(material: "steel", percent: 15)]),
                              quantities: Quantities(massKg: 0.25), rationale: "",
                              fallbackEstimates: Self.estimates([.carbon: 0.03, .water: 0.1]),
                              isReusable: true, lifespanYears: 5)
        let (original, shown) = try await swaps(for: cup, [jar])
        let swap = try #require(shown.first)
        #expect(swap.category == .household)
        let carbon = try #require(swap.metrics[.carbon])
        #expect(carbon.tier == .factorModel, "made from its own materials, not the per-use estimate")
        let embodied = 0.25 * (0.85 * 0.85 + 0.15 * 2.0)
        let engine = ImpactEngine(reference: Self.store)
        let washing = 3 * 52 * 5 * ImpactEngine.useCarbon(kWh: ImpactEngine.washKWhPerUse,
                                                          gramsPerKWh: engine.gridGramsPerKWh(for: .default))
        #expect(abs(carbon.value - (embodied + washing)) < 1e-6)
        #expect(swap.metrics[.lifespan]?.value == 5)

        let perYear = try #require(GreenScore.comparison(.carbon, original: original, alternative: swap, engine: engine))
        #expect(perYear.swap.value < perYear.current.value)
        #expect(perYear.swap.value > 0.1, "washing a jar three times a week is not free")
        #expect(GreenScore.comparison(.decompositionTime, original: original, alternative: swap, engine: engine) == nil)
    }

    // MARK: S5: second-hand, lifespans and the cache

    @Test func aUsedCarIsComparedOverTheSameYearsAndNotCached() async throws {
        // 14: "Buy a used CR-V" had the original's exact carbon; its whole gain was the AI's 10-year life against the
        // original's 5-year default, and it was then stored under bm:honda|cr-v.
        let materials = [MaterialShare(material: "steel", percent: 70), MaterialShare(material: "aluminium", percent: 10),
                         MaterialShare(material: "other_plastic", percent: 12), MaterialShare(material: "rubber", percent: 8)]
        let suv = Component(name: "Compact SUV", category: .household, identifiers: Identifiers(materials: materials),
                            quantities: Quantities(massKg: 1_400))
        let used = Alternative(name: "Buy a used compact SUV", category: .household,
                               identifiers: Identifiers(brand: "Honda", model: "CR-V", materials: materials),
                               quantities: Quantities(massKg: 1_400), rationale: "",
                               fallbackEstimates: Self.estimates([.lifespan: 10]), condition: .used, lifespanYears: 10)
        let cache = InMemoryResolutionCache()
        // A stale entry under the swap's key (from an older build) is not read either.
        await cache.store(CachedResolution(metrics: [.carbon: .exact(1, unit: .kgCO2e, tier: .estimate)]), forKey: "bm:honda|cr-v")
        let pipeline = pipeline([used], cache: cache)
        let original = await resolved(suv, in: pipeline)
        let swap = await pipeline.resolve(used, replacing: original)

        #expect(swap.metrics[.lifespan]?.value == ImpactEngine.defaultLifespanYears, "the original's years, not the AI's 10")
        let share = try #require(Alternative.Condition.used.productionShare)
        #expect(abs(try #require(swap.metrics[.carbon]).value - original.metrics[.carbon]!.value * share) < 1e-6)
        #expect(swap.metrics[.plasticMass]?.value == original.metrics[.plasticMass]?.value, "the same car, the same plastic")
        #expect(await cache.count == 1)
        #expect(await cache.cachedResolution(forKey: "bm:honda|cr-v")?.metrics[.carbon]?.value == 1)
    }

    @Test func aLongerLifeCountsOnlyWhenTheSwapIsAboutIt() async throws {
        let laptop = Component(name: "Laptop", category: .electronic, quantities: Quantities(deviceType: "laptop"),
                               usage: UsageProfile(hoursOnPerDay: 6))
        let keep = Alternative(name: "Keep it three more years with a new battery", category: .electronic,
                               quantities: Quantities(deviceType: "laptop"), rationale: "", lifespanYears: 7)
        let refurbished = Alternative(name: "Refurbished laptop", category: .electronic,
                                      quantities: Quantities(deviceType: "laptop"), rationale: "",
                                      condition: .refurbished, lifespanYears: 7)
        let efficient = Alternative(name: "Efficient laptop", category: .electronic,
                                    quantities: Quantities(deviceType: "laptop"), rationale: "",
                                    fallbackEstimates: Self.estimates([.lifespan: 9]))
        let pipeline = pipeline()
        let original = await resolved(laptop, in: pipeline)
        let originalYears = try #require(original.metrics[.lifespan]).value

        let kept = await pipeline.resolve(keep, replacing: original)
        #expect(kept.metrics[.lifespan]?.value == 7)
        let perYear = try #require(GreenScore.comparison(.carbon, original: original, alternative: kept, engine: pipeline.engine))
        #expect(perYear.swap.value < perYear.current.value)

        #expect(await pipeline.resolve(refurbished, replacing: original).metrics[.lifespan]?.value == originalYears,
                "a refurbished laptop lasts no longer than a new one")
        #expect(await pipeline.resolve(efficient, replacing: original).metrics[.lifespan]?.value == originalYears,
                "the same kind of item is compared over the same years")
    }
}
