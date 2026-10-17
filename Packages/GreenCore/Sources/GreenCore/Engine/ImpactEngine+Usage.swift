extension ImpactEngine {
    /// Applies an updated usage profile locally (spec §5.5: answering a question re-runs the engine, no network).
    /// For electronics, yearly electricity is re-derived from the power metrics and the carbon metric's use phase
    /// is shifted by the change in electricity over the item's lifespan. Food and consumables need no change:
    /// their yearly view already scales with servings/uses.
    public func applyingUsage(_ usage: UsageProfile, to component: Component, profile: UserProfile) -> Component {
        var updated = component
        updated.usage = usage
        guard component.category == .electronic,
              let newKWh = derivedYearlyElectricity(for: updated) else { return updated }
        let oldKWh = component.metrics[.yearlyElectricity]
        updated.metrics[.yearlyElectricity] = newKWh

        guard let oldKWh, let carbon = component.metrics[.carbon] else { return updated }
        let lifespanYears = lifespan(of: component).value
        let deltaKg = Self.useCarbon(kWh: newKWh.value - oldKWh.value, gramsPerKWh: gridGramsPerKWh(for: profile)) * lifespanYears
        let newValue = max(carbon.value + deltaKg, 0)
        updated.metrics[.carbon] = Measured(value: newValue, low: max(carbon.low + deltaKg, 0), high: max(carbon.high + deltaKg, newValue),
                                            unit: carbon.unit, tier: carbon.tier, sources: carbon.sources)

        // Keep the flow view consistent: grow or shrink the use stage by the same delta.
        let shares = stageShares(for: component, metric: .carbon)
        var absolute = shares.mapValues { $0 * carbon.value }
        absolute[.use, default: 0] = max((absolute[.use] ?? 0) + deltaKg, 0)
        updated.stageShares = StageModel.normalized(absolute)
        return updated
    }

    /// Applies one question answer (`AnswerOption.field` = `value`); options without a field leave the estimate.
    public func applyingAnswer(_ option: AnswerOption, to component: Component, profile: UserProfile) -> Component {
        guard let field = option.field, let value = option.value else { return component }
        return applyingUsage((component.usage ?? UsageProfile()).setting(field, to: value), to: component, profile: profile)
    }
}
