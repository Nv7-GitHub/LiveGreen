import Foundation

extension ScanPipeline {
    /// At most this many detail questions per scan, one per item, so the user is never handed a form.
    public static let maxSpecQuestions = 3

    /// How far (×) an answer may move a T4 item's carbon from the AI's own estimate. The AI saw the item, so an answer
    /// that lands further off describes something else: a single material for a car, a refrigerator for a drone.
    public static let refinementBand = 3.0

    /// Detail questions, biggest yearly carbon first: for items whose carbon is still a T4 estimate after the ladder
    /// (`SpecQuestionCatalog.candidates`), and for T3 foods whose group the AI picks inconsistently
    /// (`SpecQuestionCatalog.variants`). A question is kept only when at least two of its options really resolve
    /// through the factor model (each is tried locally), and only those options are offered; for a T4 item's make-up
    /// or size they must also land within `refinementBand` of its estimate. No network call.
    public func specQuestions(for components: [Component]) async -> [SpecQuestion] {
        guard let store = engine.store else { return [] }
        let yearly = Dictionary(uniqueKeysWithValues: components.map { ($0.id, engine.roughYearlyCarbon(of: $0)) })
        let askable = components
            .filter { $0.metrics[.carbon]?.tier == .estimate || ($0.category == .food && $0.metrics[.carbon]?.tier == .factorModel) }
            .sorted { (yearly[$0.id] ?? 0) > (yearly[$1.id] ?? 0) }
        var questions: [SpecQuestion] = []
        var askedKinds = Set<String>()
        for component in askable where questions.count < Self.maxSpecQuestions {
            // Items of one kind share their details, so one answer covers them all (`refining`).
            if let key = Self.detailKind(of: component), !askedKinds.insert(key).inserted { continue }
            let isEstimate = component.metrics[.carbon]?.tier == .estimate
            let candidates = isEstimate ? SpecQuestionCatalog.candidates(for: component, store: store)
                                        : SpecQuestionCatalog.variants(for: component, store: store)
            for var candidate in candidates {
                var working: [SpecOption] = []
                for option in candidate.options where option.setsSomething {
                    let tried = await ladder.resolve(option.applied(to: Self.clearing(component, for: option)), profile: profile,
                                                     tiers: .factorModel ... .factorModel)
                    guard let carbon = tried.metrics[.carbon], carbon.tier == .factorModel else { continue }
                    if isEstimate, candidate.topic.isCheckedAgainstEstimate,
                       !Self.isPlausible(carbon.value, against: component.metrics[.carbon]?.value) { continue }
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

    /// Whether a refined carbon is within `refinementBand` of the AI's estimate (either way); true without one.
    static func isPlausible(_ refined: Double, against estimate: Double?) -> Bool {
        guard let estimate, estimate > 0, refined > 0 else { return true }
        let ratio = refined / estimate
        return ratio <= refinementBand && ratio >= 1 / refinementBand
    }

    /// What one detail answer covers in a scan: a generic kind, barcode or model (`resolutionKey`), else for food the
    /// dish's name, so two identical puddings are asked about once.
    static func detailKind(of component: Component) -> String? {
        component.resolutionKey ?? (component.category == .food ? "food:\(component.name.lowercased())" : nil)
    }

    /// Applies detail answers (spec questions) and re-resolves those items locally: the values the answer replaces are
    /// cleared (T4 values, and a food's factor-model values when its group changes), the factor model and estimates
    /// run again on the new quantities, then derived values and totals. An answer also covers the other items of the
    /// same kind (`detailKind`) on the same tier, the ones the question was asked once for; items without an answer
    /// are unchanged. A food whose group changed takes the new group's typical week unless the user has said how often
    /// (`UsageDefaults`). Each refined item keeps what it was before (`Component.detailAnswer`), so the answer can be
    /// taken back. Refined numbers are cached under a GTIN or brand|model, like a scan, but not under a generic kind:
    /// the answer was about this item, not every item of its kind.
    public func refining(_ result: ScanResult, specAnswers: [SpecAnswer]) async -> ScanResult {
        var updated = result
        for answer in specAnswers {
            guard let answered = updated.components.first(where: { $0.id == answer.componentID }) else { continue }
            let kind = Self.detailKind(of: answered)
            for index in updated.components.indices {
                let component = updated.components[index]
                guard component.id == answered.id
                    || (kind != nil && Self.detailKind(of: component) == kind
                        && component.metrics[.carbon]?.tier == answered.metrics[.carbon]?.tier)
                else { continue }
                let refined = await refined(component, with: answer.option)
                updated.components[index] = refined
                if refined.identifiers.cacheKey != nil { await ladder.remember(refined) }
            }
        }
        updated.components = withDefaultUsage(updated.components, keepingAnswers: true)
        updated.updateTotals(engine: engine)
        return updated
    }

    func refined(_ component: Component, with option: SpecOption) async -> Component {
        let cleared = Self.clearing(component, for: option)
        var working = option.applied(to: cleared)
        working = await ladder.resolve(working, profile: profile, tiers: .factorModel ... .estimate)
        // The answer is part of the evidence now, so say so next to the table's citation.
        let note = Source(title: "Your answer: \(option.label)", tier: .factorModel)
        for (metric, value) in working.metrics where value.tier == .factorModel && cleared.metrics[metric] == nil {
            working.metrics[metric] = Measured(value: value.value, low: value.low, high: value.high, unit: value.unit,
                                               tier: value.tier, sources: value.sources + [note])
        }
        let deferrable = component.plugCandidate?.loadType
        working.plugCandidate = nil
        // A second answer to the same item still takes it back to how the scan found it.
        let before = component.detailAnswer.map { $0.restoring(component) } ?? component
        working.detailAnswer = DetailAnswer(label: option.label, before: before)
        return completed(working, deferrable: deferrable)
    }

    /// The component without the values an answer replaces, so the ladder fills them again: its T4 values (a T4
    /// carbon's stage split came from the use-phase step, so it goes too), and for an answer that changes a food's
    /// group, the factor-model values of the old group with their stage split.
    static func clearing(_ component: Component, for option: SpecOption) -> Component {
        guard option.foodGroup != nil, component.category == .food else { return clearingEstimates(component) }
        var result = component
        result.stageShares = [:]
        result.metrics = result.metrics.filter { $0.value.tier < .factorModel }
        return result
    }

    /// The component without its T4 values, so the ladder fills them again. A T4 carbon's stage split came from
    /// the use-phase step, so it goes too.
    static func clearingEstimates(_ component: Component) -> Component {
        var result = component
        if result.metrics[.carbon]?.tier == .estimate { result.stageShares = [:] }
        result.metrics = result.metrics.filter { $0.value.tier != .estimate }
        return result
    }

    /// Takes back a detail answer from the item's detail sheet: the item returns to the identity and numbers it had
    /// before the answer (`DetailAnswer.restoring`), and so do the items of its kind the same answer refined. Usage set
    /// since is kept and re-applied, so an electronic's electricity matches its hours; a food back on its old group
    /// takes that group's typical week unless the user has said how often. A GTIN or brand|model the answer was cached
    /// under gets its scanned numbers back. No network call.
    public func undoingDetail(of componentID: UUID, in result: ScanResult) async -> ScanResult {
        guard let answered = result.component(withID: componentID), let answer = answered.detailAnswer else { return result }
        let kind = Self.detailKind(of: answered)
        var updated = result
        for index in updated.components.indices {
            let component = updated.components[index]
            guard component.id == componentID
                || (kind != nil && Self.detailKind(of: component) == kind && component.detailAnswer?.label == answer.label),
                let detail = component.detailAnswer else { continue }
            var restored = detail.restoring(component)
            if let usage = restored.usage { restored = engine.applyingUsage(usage, to: restored, profile: profile) }
            updated.components[index] = restored
            if restored.identifiers.cacheKey != nil { await ladder.remember(restored) }
        }
        updated.components = withDefaultUsage(updated.components, keepingAnswers: true)
        updated.updateTotals(engine: engine)
        return updated
    }
}

extension ImpactEngine {
    /// Point estimate of a component's yearly carbon, to rank items without a Monte Carlo run.
    func roughYearlyCarbon(of component: Component) -> Double {
        guard let carbon = component.metrics[.carbon]?.value else { return 0 }
        switch annualBasis(for: component) {
        case let .unitsPerYear(units): return carbon * units
        case let .lifetime(lifespan): return lifespan.value > 0 ? carbon / lifespan.value : carbon
        }
    }
}
