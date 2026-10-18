/// Decides which proposed questions to show (spec §5.5): the component must be one of the scan's top-two yearly
/// carbon contributors, and the question must narrow something: one of its affected metrics has a wide range
/// (high/low > 1.6), or it asks how often a consumable is had while that rate is still a typical-week assumption
/// (`UsageDefaults`). Options that would change nothing are dropped (an identify question about a dumpling's filling
/// can only set usage fields), and so is a question left with fewer than two.
public enum QuestionGate {
    public static let spreadThreshold = 1.6

    /// LiveGreen's own frequency question (`ScanPipeline.askingFrequency`), for consumables identify asked nothing about.
    public static let frequencyQuestionID = "livegreen_frequency"

    /// Usage fields that set how often a consumable is had.
    static let rateFields: Set<UsageField> = [.servingsPerWeek, .packsPerWeek, .usesPerWeek]

    public static func pendingQuestions(for components: [Component], engine: ImpactEngine = ImpactEngine()) -> [PendingQuestion] {
        // Ranked per year, like the results: a laptop's lifetime carbon is not 250 times a latte's.
        let topCarbon = components
            .filter { $0.metrics[.carbon] != nil }
            .map { ($0.id, engine.roughYearlyCarbon(of: $0)) }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map(\.0)
        return components.filter { topCarbon.contains($0.id) }.flatMap { component in
            let fields = effectiveFields(for: component, engine: engine)
            return component.questions.compactMap { proposed -> PendingQuestion? in
                var question = proposed
                question.options = proposed.options.filter { $0.value != nil && $0.field.map(fields.contains) == true }
                guard question.options.count >= 2 else { return nil }
                let assumedRate = component.usage?.source == .typical && question.options.contains { $0.field.map(rateFields.contains) == true }
                guard assumedRate || question.affectedMetrics.contains(where: { (component.metrics[$0]?.spreadRatio ?? 0) > spreadThreshold })
                else { return nil }
                var pending = PendingQuestion(componentID: component.id, componentName: component.name, question: question)
                pending.currentValue = pending.field.flatMap { currentValue(of: $0, for: component, engine: engine) }
                return pending
            }
        }
    }

    /// Usage fields that move this component's numbers: the ones its usage card edits, servings for a per-pack food
    /// (identify asks in servings; `ImpactEngine.applyingAnswer` turns them into packs) and charges for battery devices.
    static func effectiveFields(for component: Component, engine: ImpactEngine) -> Set<UsageField> {
        var fields = Set(engine.editableUsage(for: component).map(\.field))
        if fields.contains(.packsPerWeek) { fields.insert(.servingsPerWeek) }
        if engine.batteryKWh(for: component) != nil { fields.insert(.chargesPerWeek) }
        return fields
    }

    /// The value the numbers use now for `field` (a per-pack food's servings counted from its packs), so the sheet can
    /// show "Now: 3 a week" and offer it.
    public static func currentValue(of field: UsageField, for component: Component,
                                    engine: ImpactEngine = ImpactEngine()) -> Double? {
        if field == .servingsPerWeek, FoodServing.isPerPack(component) {
            return FoodServing.servingView(of: component).usage?.servingsPerWeek
        }
        return engine.editableUsage(for: component).first { $0.field == field }?.value ?? component.usage?[field]
    }

    /// Drops questions the user has answered or declined ("Use estimate"), so a saved scan doesn't ask again.
    public static func settling(_ settled: [PendingQuestion], in components: [Component]) -> [Component] {
        let ids = Set(settled.map(\.id))
        return components.map { component in
            var updated = component
            updated.questions.removeAll { question in
                ids.contains(PendingQuestion(componentID: component.id, componentName: component.name,
                                             question: question).id)
            }
            return updated
        }
    }
}
