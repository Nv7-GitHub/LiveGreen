import Foundation
import Testing
@testable import GreenCore

@Suite("Swap math")
struct SwapMathTests {
    private static func measured(_ metric: MetricKey, _ value: Double) -> Measured {
        Measured(value: value, relativeRange: 0.2, unit: metric.unit, tier: .factorModel)
    }

    private static func metrics(_ values: [MetricKey: Double]) -> [MetricKey: Measured] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.key, measured($0.key, $0.value)) })
    }

    private static func label(_ metric: MetricKey, _ current: Double, _ swap: Double) -> String? {
        SwapMath.change(metric, current: measured(metric, current), alternative: measured(metric, swap))?.label
    }

    // MARK: S7: how a change reads

    @Test func sharesAndScoresChangeByPoints() {
        #expect(Self.label(.recyclablePercent, 2.7, 90) == "+87 pts", "not 3,233% better")
        #expect(Self.label(.recyclablePercent, 31.1, 90) == "+59 pts")
        #expect(Self.label(.recyclablePercent, 70, 50) == "−20 pts")
        #expect(Self.label(.repairability, 4, 6.5) == "+2.5 pts")
        #expect(Self.label(.recyclablePercent, 68.2, 68) == nil, "rounds to no change")
    }

    @Test func aHundredPercentBetterOnlyWhenTheSwapIsZero() {
        #expect(Self.label(.carbon, 2.86, 0.003) == ">99% better")
        #expect(Self.label(.plasticMass, 5.5, 0) == "100% better")
        #expect(Self.label(.carbon, 10, 4) == "60% better")
        #expect(Self.label(.lifespan, 5, 10) == "100% better", "twice the life is a real doubling")
    }

    @Test func bigRisesReadAsMultiplesAndRisesFromZeroAsWorse() {
        #expect(Self.label(.decompositionTime, 0.1, 450) == "4500× worse")
        #expect(Self.label(.carbon, 1, 1.5) == "50% worse")
        #expect(Self.label(.plasticMass, 0, 5) == "Worse")
        #expect(Self.label(.carbon, 1, 1.004) == nil)
    }

    // MARK: S8, S8b: the card counts what it shows

    @Test func theTallyCountsOnlyTheMetricsShown() {
        // 25: a digital flyer whose AI-given recyclability (68.2 → 68%) and decomposition (0.1 → 0.1 yr) do not
        // change. They are not shown, so they are not counted either.
        let flyer = Component(name: "Paper flyer", category: .packaging,
                              metrics: Self.metrics([.carbon: 0.0033, .water: 0.09, .recyclablePercent: 68.2,
                                                     .decompositionTime: 0.1]),
                              usage: UsageProfile(usesPerWeek: 1))
        let digital = Alternative(name: "Digital flyer", category: .packaging, usage: flyer.usage, rationale: "",
                                  metrics: Self.metrics([.carbon: 0.0005, .water: 0.01, .recyclablePercent: 68,
                                                         .decompositionTime: 0.1]))
        #expect(SwapMath.shownMetrics(flyer, digital) == [.carbon, .water])
        #expect(SwapMath.tally(flyer, digital) == SwapMath.Tally(better: 2, worse: 0))
    }

    @Test func everyChangedMetricIsShownDecompositionIncluded() {
        // 26: the notebook's biggest change, 450 → 1 yr, was never on screen.
        let notebook = Component(name: "Notebook", category: .household,
                                 metrics: Self.metrics([.carbon: 0.36, .water: 9, .waterPollution: 1, .plasticMass: 50,
                                                        .recyclablePercent: 40, .decompositionTime: 450, .lifespan: 2]))
        let recycled = Alternative(name: "Recycled-paper notebook", category: .household, rationale: "",
                                   metrics: Self.metrics([.carbon: 0.25, .water: 6, .waterPollution: 0.8, .plasticMass: 2,
                                                          .recyclablePercent: 85, .decompositionTime: 1, .lifespan: 2]))
        let shown = SwapMath.shownMetrics(notebook, recycled)
        #expect(shown.contains(.decompositionTime))
        #expect(shown.count == 6, "lifespan is unchanged")
        #expect(SwapMath.keyMetrics(notebook, recycled).count == SwapMath.chartLimit)
        #expect(SwapMath.tally(notebook, recycled).total == shown.count)
        #expect(Set(SwapMath.chartPriority) == Set(MetricKey.allCases))
    }

    // MARK: S6: default pick

    @Test func theDefaultPickNeverAddsCarbon() throws {
        // 11: an ENERGY STAR freezer with the best average score but 14% more carbon was preselected.
        let freezer = Component(name: "Display freezer", category: .electronic,
                                metrics: Self.metrics([.carbon: 1_460, .powerOn: 300, .standbyPower: 10,
                                                       .yearlyElectricity: 1_000, .lifespan: 14, .plasticMass: 20_000]))
        let moreCarbon = Alternative(name: "ENERGY STAR chest freezer", category: .electronic, rationale: "",
                                     metrics: Self.metrics([.carbon: 1_660, .powerOn: 150, .standbyPower: 4,
                                                            .yearlyElectricity: 600, .lifespan: 14, .plasticMass: 12_000]))
        let lessCarbon = Alternative(name: "Smaller freezer", category: .electronic, rationale: "",
                                     metrics: Self.metrics([.carbon: 1_300, .powerOn: 280, .standbyPower: 9,
                                                            .yearlyElectricity: 950, .lifespan: 14, .plasticMass: 19_000]))
        #expect(SwapMath.score(moreCarbon, freezer) > SwapMath.score(lessCarbon, freezer))
        #expect(SwapMath.raisesCarbon(freezer, moreCarbon))
        #expect(SwapMath.defaultPick(for: freezer, among: [moreCarbon, lessCarbon])?.id == lessCarbon.id)
        #expect(SwapMath.defaultPick(for: freezer, among: [moreCarbon]) == nil, "keeps the original")
    }

    // MARK: S9: card order

    @Test func cardsAreOrderedByTheirBiggestYearlySaving() {
        func food(_ name: String, carbon: Double) -> Component {
            Component(name: name, category: .food, metrics: Self.metrics([.carbon: carbon]),
                      usage: UsageProfile(servingsPerWeek: 1))
        }
        func swap(_ carbon: Double) -> Alternative {
            Alternative(name: "Swap", category: .food, usage: UsageProfile(servingsPerWeek: 1), rationale: "",
                        metrics: Self.metrics([.carbon: carbon]))
        }
        let greens = food("Greens", carbon: 0.05), rice = food("Rice", carbon: 0.7), stew = food("Stew", carbon: 0.4)
        let bare = food("Water", carbon: 0.01)
        let options: [UUID: [Alternative]] = [greens.id: [swap(0.045)], rice.id: [swap(0.2), swap(0.5)],
                                              stew.id: [swap(0.3)], bare.id: []]
        let ordered = SwapMath.byYearlySaving([greens, bare, rice, stew]) { options[$0.id] ?? [] }
        #expect(ordered.map(\.name) == ["Rice", "Stew", "Greens", "Water"])
    }
}
