import Foundation

extension ScanPipeline {
    /// At most this many detail questions per scan, one per item, so the user is never handed a form.
    public static let maxSpecQuestions = 3

    /// Detail questions for the items whose carbon is still a T4 estimate after the ladder, biggest yearly carbon
    /// first. A question is kept only when its answers really move the item to the factor model (each option is
    /// tried locally), and only options that do are offered. No network call.
    public func specQuestions(for components: [Component]) async -> [SpecQuestion] {
        guard let store = engine.store else { return [] }
        let yearly = Dictionary(uniqueKeysWithValues: components.map { ($0.id, yearlyCarbon(of: $0)) })
        let estimated = components
            .filter { $0.metrics[.carbon]?.tier == .estimate }
            .sorted { (yearly[$0.id] ?? 0) > (yearly[$1.id] ?? 0) }
        var questions: [SpecQuestion] = []
        for component in estimated where questions.count < Self.maxSpecQuestions {
            for var candidate in SpecQuestionCatalog.candidates(for: component, store: store) {
                var working: [SpecOption] = []
                for option in candidate.options where await resolvesCarbon(option.applied(to: Self.clearingEstimates(component))) {
                    working.append(option)
                }
                guard working.count >= 2 else { continue }
                candidate.options = working
                questions.append(candidate)
                break
            }
        }
        return questions
    }

    /// Applies detail answers (spec questions) and re-resolves those items locally: their T4 values are cleared,
    /// the factor model and estimates run again on the new quantities, then derived values and totals. Items
    /// without an answer are unchanged. The refined numbers are cached under the item's identifier, like a scan.
    public func refining(_ result: ScanResult, specAnswers: [SpecAnswer]) async -> ScanResult {
        var updated = result
        for answer in specAnswers {
            guard let index = updated.components.firstIndex(where: { $0.id == answer.componentID }) else { continue }
            let refined = await refined(updated.components[index], with: answer.option)
            updated.components[index] = refined
            await ladder.remember(refined)
        }
        updated.updateTotals(engine: engine)
        return updated
    }

    func refined(_ component: Component, with option: SpecOption) async -> Component {
        var working = Self.clearingEstimates(option.applied(to: component))
        working = await ladder.resolve(working, profile: profile, tiers: .factorModel ... .estimate)
        // The answer is part of the evidence now, so say so next to the table's citation.
        let note = Source(title: "Your answer: \(option.label)", tier: .factorModel)
        for (metric, value) in working.metrics where value.tier == .factorModel && component.metrics[metric]?.tier != .factorModel {
            working.metrics[metric] = Measured(value: value.value, low: value.low, high: value.high, unit: value.unit,
                                               tier: value.tier, sources: value.sources + [note])
        }
        let deferrable = component.plugCandidate?.loadType
        working.plugCandidate = nil
        return completed(working, deferrable: deferrable)
    }

    /// The component without its T4 values, so the ladder fills them again. A T4 carbon's stage split came from
    /// the use-phase step, so it goes too.
    static func clearingEstimates(_ component: Component) -> Component {
        var result = component
        if result.metrics[.carbon]?.tier == .estimate { result.stageShares = [:] }
        result.metrics = result.metrics.filter { $0.value.tier != .estimate }
        return result
    }

    private func resolvesCarbon(_ component: Component) async -> Bool {
        let resolved = await ladder.resolve(component, profile: profile, tiers: .factorModel ... .factorModel)
        return resolved.metrics[.carbon]?.tier == .factorModel
    }

    /// Point estimate of a component's yearly carbon, to rank items without a Monte Carlo run.
    private func yearlyCarbon(of component: Component) -> Double {
        guard let carbon = component.metrics[.carbon]?.value else { return 0 }
        switch engine.annualBasis(for: component) {
        case let .unitsPerYear(units): return carbon * units
        case let .lifetime(lifespan): return lifespan.value > 0 ? carbon / lifespan.value : carbon
        }
    }
}
