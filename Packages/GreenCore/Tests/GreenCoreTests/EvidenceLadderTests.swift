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
                // Records and estimates only: unpackaged food has no end-of-life figures to give.
                let unpackaged = component.category == .food && !FoodServing.isPackaged(component)
                let allowed: Set<MetricKey> = unpackaged ? [.plasticMass, .recyclablePercent, .decompositionTime] : []
                #expect(Set(component.missingMetrics).isSubset(of: allowed), "\(scene) \(component.name) missing \(component.missingMetrics)")
            }
            #expect(result.totals[.carbon] != nil)
        }
    }
}

@Suite("Question gate")
struct QuestionGateTests {
    private static let hours = [AnswerOption(label: "~2 h", field: .hoursOnPerDay, value: 2),
                                AnswerOption(label: "~8 h", field: .hoursOnPerDay, value: 8)]

    private func component(_ name: String, carbon: Double, low: Double, high: Double, question: Bool,
                           options: [AnswerOption] = hours) -> Component {
        var c = Component(name: name, category: .electronic)
        c.metrics[.carbon] = Measured(value: carbon, low: low, high: high, unit: .kgCO2e, tier: .estimate)
        if question {
            c.questions = [ComponentQuestion(id: "q", question: "Hours?", whyItMatters: "Use phase",
                                             affectedMetrics: [.carbon], options: options)]
        }
        return c
    }

    @Test func onlyWideTopTwoContributorsAsk() {
        let big = component("Big", carbon: 400, low: 200, high: 650, question: true)
        let narrow = component("Narrow", carbon: 300, low: 280, high: 320, question: true)
        let small = component("Small", carbon: 5, low: 1, high: 20, question: true)
        let pending = QuestionGate.pendingQuestions(for: [small, narrow, big])
        #expect(pending.map(\.componentName) == ["Big"])
        // The sheet shows what the numbers use now: the device table's typical hours without a stated usage.
        #expect(pending.first?.currentValue == 4)
    }

    @Test func settledQuestionsStopAsking() {
        let big = component("Big", carbon: 400, low: 200, high: 650, question: true)
        let pending = QuestionGate.pendingQuestions(for: [big])
        #expect(pending.count == 1)
        let settled = QuestionGate.settling(pending, in: [big])
        #expect(QuestionGate.pendingQuestions(for: settled).isEmpty)
        #expect(settled[0].metrics == big.metrics)
    }

    /// Identify once asked what dumplings were filled with, with options that set no usage field: answering changed
    /// nothing. Such options, and options for a field that does not move the item's numbers, are never offered.
    @Test func optionsThatChangeNothingAreDropped() {
        let filling = [AnswerOption(label: "Vegetable"), AnswerOption(label: "Pork")]
        let inert = component("Dumplings", carbon: 400, low: 200, high: 650, question: true, options: filling)
        #expect(QuestionGate.pendingQuestions(for: [inert]).isEmpty)
        let wearsOnly = [AnswerOption(label: "Rarely", field: .wearsPerYear, value: 5),
                         AnswerOption(label: "Often", field: .wearsPerYear, value: 100)]
        let wrongField = component("Laptop", carbon: 400, low: 200, high: 650, question: true, options: wearsOnly)
        #expect(QuestionGate.pendingQuestions(for: [wrongField]).isEmpty)
        let mixed = component("Monitor", carbon: 400, low: 200, high: 650, question: true,
                              options: Self.hours + [AnswerOption(label: "Not sure")])
        #expect(QuestionGate.pendingQuestions(for: [mixed]).first?.question.options == Self.hours)
    }

    /// Per year a daily latte outweighs a laptop's share of its making, so the latte's question is the one shown.
    @Test func topContributorsAreRankedPerYear() {
        let laptop = component("Laptop", carbon: 250, low: 120, high: 400, question: true)
        var latte = Component(name: "Iced latte", category: .food, quantities: Quantities(volumeLiters: 0.45, foodGroup: "latte"),
                              usage: UsageProfile(servingsPerWeek: 7, source: .answered))
        latte.metrics[.carbon] = Measured(value: 0.8, low: 0.4, high: 1.6, unit: .kgCO2e, tier: .factorModel)
        latte.questions = [ComponentQuestion(id: "servings", question: "How often?", whyItMatters: "Frequency",
                                             affectedMetrics: [.carbon],
                                             options: [AnswerOption(label: "Weekly", field: .servingsPerWeek, value: 1),
                                                       AnswerOption(label: "Daily", field: .servingsPerWeek, value: 7)])]
        var mouse = component("Mouse", carbon: 10, low: 5, high: 20, question: false)
        mouse.metrics[.lifespan] = .exact(5, unit: .years, tier: .factorModel)
        let pending = QuestionGate.pendingQuestions(for: [laptop, latte, mouse])
        #expect(Set(pending.map(\.componentName)) == ["Laptop", "Iced latte"])
        #expect(pending.first { $0.componentName == "Iced latte" }?.currentValue == 7)
    }
}
