import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("GreenScore")
struct GreenScoreTests {
    private static func measured(_ metric: MetricKey, _ value: Double) -> Measured {
        Measured(value: value, relativeRange: 0.2, unit: metric.unit, tier: .factorModel)
    }

    private static func metrics(_ values: [MetricKey: Double]) -> [MetricKey: Measured] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.key, measured($0.key, $0.value)) })
    }

    /// A burger eaten once a week, per serving.
    private static let burger = Component(
        name: "Beef burger", category: .food,
        metrics: metrics([.carbon: 10, .water: 200, .land: 30, .waterPollution: 40, .plasticMass: 5]),
        usage: UsageProfile(servingsPerWeek: 1))

    private static func swap(_ values: [MetricKey: Double], category: GreenCore.Category = .food,
                             kind: Alternative.Kind = .product) -> Alternative {
        Alternative(kind: kind, name: "Swap", category: category, usage: burger.usage, rationale: "",
                    metrics: metrics(values))
    }

    @Test func betterOnEveryMetricIsAcceptedWithAPositiveScore() {
        let assessment = GreenScore.assess(Self.swap([.carbon: 4, .water: 100, .land: 12, .waterPollution: 20,
                                                      .plasticMass: 5]), replacing: Self.burger)
        #expect(assessment.isAcceptable)
        #expect(assessment.score > 0.3)
        #expect(assessment.changes[.plasticMass] == 0, "an unchanged metric still counts, as zero")
        #expect(assessment.changes.count == 5)
    }

    @Test func bigCarbonCutWithMuchMoreWaterIsRejected() {
        // Carbon −80%, but water 3× worse: the average is positive, the trade-off still rules it out.
        let assessment = GreenScore.assess(Self.swap([.carbon: 2, .water: 600, .land: 15, .waterPollution: 20,
                                                      .plasticMass: 5]), replacing: Self.burger)
        #expect(assessment.score > 0)
        #expect(!assessment.isAcceptable)
        #expect(assessment.worstMetric == .water)
    }

    @Test func bigCarbonCutWithMuchMorePlasticIsRejected() {
        let assessment = GreenScore.assess(Self.swap([.carbon: 1, .water: 150, .land: 20, .waterPollution: 30,
                                                      .plasticMass: 40]), replacing: Self.burger)
        #expect(!assessment.isAcceptable)
        #expect(assessment.worstMetric == .plasticMass)
    }

    @Test func noMetricDominatesTheScore() {
        // 100× less carbon and nothing else changes: clamped to 4×, so the mean stays modest.
        let assessment = GreenScore.assess(Self.swap([.carbon: 0.1, .water: 200, .land: 30, .waterPollution: 40,
                                                      .plasticMass: 5]), replacing: Self.burger)
        #expect(abs(assessment.score - log(4) / 5) < 1e-9)
    }

    @Test func higherIsBetterMetricsAreFlipped() throws {
        let lamp = Component(name: "Lamp", category: .household,
                             metrics: Self.metrics([.carbon: 20, .lifespan: 10, .recyclablePercent: 50]))
        let shorterLived = Alternative(name: "Cheap lamp", category: .household, rationale: "",
                                       metrics: Self.metrics([.carbon: 18, .lifespan: 4, .recyclablePercent: 50]))
        let assessment = GreenScore.assess(shorterLived, replacing: lamp)
        #expect(try #require(assessment.changes[.lifespan]) < 0)
        #expect(!assessment.isAcceptable, "lifespan 10 → 4 years is a big loss")
    }

    @Test func tinyAndZeroAmountsDoNotCount() throws {
        // Standby 0.6 → 1 W is a 67% rise but a small amount; plastic 0 → 0 is not a metric at all.
        let monitor = Component(name: "Monitor", category: .electronic,
                                metrics: Self.metrics([.carbon: 400, .standbyPower: 0.6, .plasticMass: 0, .lifespan: 6]))
        let efficient = Alternative(name: "Efficient monitor", category: .electronic, rationale: "",
                                    metrics: Self.metrics([.carbon: 250, .standbyPower: 1, .plasticMass: 0, .lifespan: 6]))
        let assessment = GreenScore.assess(efficient, replacing: monitor)
        #expect(assessment.changes[.plasticMass] == nil)
        #expect(try #require(assessment.changes[.standbyPower]) > -log(1 + GreenScore.maxWorsening))
        #expect(assessment.isAcceptable)
    }

    @Test func plasticAppearingWhereThereWasNoneIsATradeOff() {
        let assessment = GreenScore.assess(Self.swap([.carbon: 4, .water: 100, .land: 12, .waterPollution: 20,
                                                      .plasticMass: 30]),
                                           replacing: Component(name: "Loose apples", category: .food,
                                                                metrics: Self.metrics([.carbon: 10, .water: 200, .land: 30,
                                                                                       .waterPollution: 40, .plasticMass: 0]),
                                                                usage: Self.burger.usage))
        #expect(!assessment.isAcceptable)
    }

    @Test func reusablesAreComparedPerYearOfTheSameJob() throws {
        // One steel cup has far more carbon than one paper cup, but it replaces a year of them (5 a week) over its
        // 5-year life. How long one cup lingers against one steel cup says nothing, so decomposition is left out.
        let paper = Component(name: "Paper cup", category: .packaging,
                              metrics: Self.metrics([.carbon: 0.03, .water: 0.5, .plasticMass: 2, .decompositionTime: 0.3]),
                              usage: UsageProfile(usesPerWeek: 5))
        let steel = Alternative(name: "Steel cup", category: .household, usage: paper.usage, rationale: "",
                                metrics: Self.metrics([.carbon: 1.5, .water: 20, .plasticMass: 5, .decompositionTime: 50,
                                                       .lifespan: 5]))
        let assessment = GreenScore.assess(steel, replacing: paper)
        #expect(assessment.isAcceptable)
        #expect(try #require(assessment.changes[.carbon]) > 0)
        #expect(assessment.changes[.decompositionTime] == nil)
    }

    @Test func aGlassJarIsNotHiddenByGlassLastingAMillionYears() throws {
        // S1: PET cups at 3 a week against a reusable glass jar. Decomposition was annualized (1,000,000 yr ÷ 5 vs
        // 450 × 156), read as 8.5× worse and vetoed the jar.
        let cups = Component(name: "PET cup", category: .packaging,
                             metrics: Self.metrics([.carbon: 0.03, .water: 0.6, .plasticMass: 10, .recyclablePercent: 5,
                                                    .decompositionTime: 450]),
                             usage: UsageProfile(usesPerWeek: 3))
        let jar = Alternative(name: "Reusable glass jar", category: .household, usage: cups.usage, rationale: "",
                              metrics: Self.metrics([.carbon: 6, .water: 50, .plasticMass: 0, .recyclablePercent: 31,
                                                     .decompositionTime: 1_000_000, .lifespan: 5]),
                              isReusable: true)
        let assessment = GreenScore.assess(jar, replacing: cups)
        #expect(assessment.isAcceptable)
        #expect(assessment.changes[.decompositionTime] == nil)
        #expect(GreenScore.comparison(.decompositionTime, original: cups, alternative: jar, engine: ImpactEngine()) == nil)
    }

    @Test func decompositionIsPerItemCappedAndNeverVetoes() throws {
        // Two single-use bottles: glass (inert, a million years) against PET (450). Per item and capped at 500 years,
        // that is a small step, not a 2,000× loss.
        let pet = Component(name: "PET bottle", category: .packaging,
                            metrics: Self.metrics([.carbon: 0.08, .plasticMass: 25, .recyclablePercent: 29,
                                                   .decompositionTime: 450]),
                            usage: UsageProfile(usesPerWeek: 2))
        let glass = Alternative(name: "Glass bottle", category: .packaging, usage: pet.usage, rationale: "",
                                metrics: Self.metrics([.carbon: 0.07, .plasticMass: 1, .recyclablePercent: 31,
                                                       .decompositionTime: 1_000_000]))
        let values = try #require(GreenScore.comparison(.decompositionTime, original: pet, alternative: glass,
                                                        engine: ImpactEngine()))
        #expect(!values.annualized, "decomposition is compared per item")
        let change = try #require(GreenScore.assess(glass, replacing: pet).changes[.decompositionTime])
        #expect(abs(change - log(450.5 / 500.5)) < 1e-9)

        // Paper lasting months against film lasting decades is a big decomposition loss, but plastic and
        // recyclability carry that harm; decomposition alone does not veto.
        let paperBag = Component(name: "Paper bag", category: .packaging,
                                 metrics: Self.metrics([.carbon: 0.05, .water: 1.5, .plasticMass: 0, .recyclablePercent: 68,
                                                        .decompositionTime: 0.1]),
                                 usage: UsageProfile(usesPerWeek: 2))
        let lighter = Alternative(name: "Thin compostable film bag", category: .packaging, usage: paperBag.usage,
                                  rationale: "", metrics: Self.metrics([.carbon: 0.01, .water: 0.3, .plasticMass: 0,
                                                                        .recyclablePercent: 68, .decompositionTime: 20]))
        let assessment = GreenScore.assess(lighter, replacing: paperBag)
        #expect(try #require(assessment.changes[.decompositionTime]) < -log(1 + GreenScore.maxWorsening))
        #expect(assessment.isAcceptable)
    }

    @Test func theSameFoodUnderAnotherNameIsNotASwap() {
        // S2: brown rice for white rice, or "local seasonal" broccoli: same food group, so the same factors; any
        // gap comes from the two sides resting on different evidence.
        let rice = Component(name: "White rice", category: .food, quantities: Quantities(servingKg: 0.15, foodGroup: "rice"),
                             metrics: Self.metrics([.carbon: 0.67, .water: 337, .land: 0.42, .waterPollution: 5]),
                             usage: UsageProfile(servingsPerWeek: 3))
        let brown = Alternative(name: "Brown rice", category: .food,
                                quantities: Quantities(servingKg: 0.15, foodGroup: "rice"), usage: rice.usage,
                                rationale: "", metrics: Self.metrics([.carbon: 0.6, .water: 300, .land: 0.38,
                                                                      .waterPollution: 4.5]))
        let assessment = GreenScore.assess(brown, replacing: rice)
        #expect(assessment.score > GreenScore.minimumScore)
        #expect(assessment.isRelabelledFood)
        #expect(!assessment.isAcceptable)
        #expect(GreenScore.ranked([brown], replacing: rice).isEmpty)

        // Aliases name one group ("lentils" and "beans" are both other_pulses).
        let lentils = Component(name: "Lentil stew", category: .food,
                                quantities: Quantities(servingKg: 0.3, foodGroup: "lentils"), usage: rice.usage)
        let bulk = Alternative(name: "Bulk dried beans", category: .food,
                               quantities: Quantities(servingKg: 0.3, foodGroup: "beans"), rationale: "")
        #expect(GreenScore.isRelabelledFood(bulk, replacing: lentils, engine: ImpactEngine()))

        // A smaller portion or a different food is a real change.
        var smaller = brown
        smaller.quantities.servingKg = 0.1
        #expect(!GreenScore.isRelabelledFood(smaller, replacing: rice, engine: ImpactEngine()))
        var bulgur = brown
        bulgur.quantities.foodGroup = "wheat"
        #expect(!GreenScore.isRelabelledFood(bulgur, replacing: rice, engine: ImpactEngine()))
    }

    @Test func rankingDropsTradeOffsOrdersByScoreAndKeepsThePlugLast() {
        let small = Self.swap([.carbon: 8, .water: 180, .land: 27, .waterPollution: 36, .plasticMass: 5])
        let big = Self.swap([.carbon: 4, .water: 100, .land: 12, .waterPollution: 20, .plasticMass: 4])
        let tradeOff = Self.swap([.carbon: 1, .water: 900, .land: 5, .waterPollution: 5, .plasticMass: 1])
        let flat = Self.swap([.carbon: 10, .water: 200, .land: 30, .waterPollution: 40, .plasticMass: 5])
        let plug = Alternative.smartPlugScheduling(for: Self.burger)
        let ranked = GreenScore.ranked([small, plug, tradeOff, flat, big], replacing: Self.burger)
        #expect(ranked.map(\.id) == [big.id, small.id, plug.id])
    }

    @Test func pipelineSwapsPassTheTradeOffRule() async throws {
        let store = ReferenceStore.bundled
        let resolvers: [any MetricResolver] = [ASUSPCFResolver(store: store), FactorModelResolver(store: store),
                                               EstimateResolver()]
        let pipeline = ScanPipeline(vision: FakeVisionIdentifier(scene: .deskSetup), alternatives: FakeAlternativeSuggester(),
                                    products: FakeProductDatabase(), ladder: EvidenceLadder(resolvers: resolvers),
                                    engine: ImpactEngine(reference: store), profile: .default)
        let result = try await pipeline.suggestAlternatives(for: pipeline.run(image: Data([1]), hints: .none, mode: .photo))
        for component in result.components {
            #expect(component.alternatives.contains { $0.kind == .product }, "demo swaps improve every metric")
            for alternative in component.alternatives {
                #expect(GreenScore.accepts(alternative, replacing: component))
            }
        }
    }
}
