import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Evidence ladder")
struct EvidenceLadderTests {
    let component = Component(name: "Monitor", category: .electronic,
                              fallbackEstimates: [.carbon: EstimateRange(value: 400, low: 300, high: 500)])

    @Test func lowerTiersWinAndHigherTiersFillGaps() async {
        let ladder = EvidenceLadder(resolvers: [
            FakeMetricResolver(tier: .factorModel, values: [.powerOn: 30, .lifespan: 6]),
            FakeMetricResolver(tier: .exactRecord, values: [.powerOn: 18]),
            EstimateResolver(),
        ])
        let resolved = await ladder.resolve(component, profile: .default)
        #expect(resolved.metrics[.powerOn]?.value == 18)
        #expect(resolved.metrics[.powerOn]?.tier == .exactRecord)
        #expect(resolved.metrics[.lifespan]?.tier == .factorModel)
        #expect(resolved.metrics[.carbon]?.tier == .estimate)
        #expect(resolved.metrics[.standbyPower] == nil)
    }

    @Test func failingResolverFallsThrough() async {
        let ladder = EvidenceLadder(resolvers: [FakeMetricResolver.failing(tier: .exactRecord), EstimateResolver()])
        let resolved = await ladder.resolve(component, profile: .default)
        #expect(resolved.metrics[.carbon]?.tier == .estimate)
    }

    @Test func estimatesAreWidenedToAtLeastFiftyPercent() async {
        let resolved = await EvidenceLadder(resolvers: [EstimateResolver()]).resolve(component, profile: .default)
        let carbon = try! #require(resolved.metrics[.carbon])
        #expect(carbon.low == 200)
        #expect(carbon.high == 600)
    }

    @Test func demoScenesResolveEveryApplicableMetric() async {
        for scene in DemoScene.allCases {
            let result = await SampleScans.resolved(scene)
            #expect(!result.components.isEmpty)
            for component in result.components {
                #expect(component.missingMetrics.isEmpty, "\(scene) \(component.name) missing \(component.missingMetrics)")
            }
            #expect(result.totals[.carbon] != nil)
        }
    }
}

@Suite("Question gate")
struct QuestionGateTests {
    private func component(_ name: String, carbon: Double, low: Double, high: Double, question: Bool) -> Component {
        var c = Component(name: name, category: .electronic)
        c.metrics[.carbon] = Measured(value: carbon, low: low, high: high, unit: .kgCO2e, tier: .estimate)
        if question {
            c.questions = [ComponentQuestion(id: "q", question: "Hours?", whyItMatters: "Use phase",
                                             affectedMetrics: [.carbon], options: [])]
        }
        return c
    }

    @Test func onlyWideTopTwoContributorsAsk() {
        let big = component("Big", carbon: 400, low: 200, high: 650, question: true)
        let narrow = component("Narrow", carbon: 300, low: 280, high: 320, question: true)
        let small = component("Small", carbon: 5, low: 1, high: 20, question: true)
        let pending = QuestionGate.pendingQuestions(for: [small, narrow, big])
        #expect(pending.map(\.componentName) == ["Big"])
    }

    @Test func settledQuestionsStopAsking() {
        let big = component("Big", carbon: 400, low: 200, high: 650, question: true)
        let pending = QuestionGate.pendingQuestions(for: [big])
        let settled = QuestionGate.settling(pending, in: [big])
        #expect(QuestionGate.pendingQuestions(for: settled).isEmpty)
        #expect(settled[0].metrics == big.metrics)
    }
}
