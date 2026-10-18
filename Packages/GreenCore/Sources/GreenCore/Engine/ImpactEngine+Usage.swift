extension ImpactEngine {
    /// Applies an updated usage profile locally (spec §5.5: answering a question re-runs the engine, no network).
    /// For electronics, yearly electricity is re-derived from the power metrics and the carbon metric's use phase
    /// is shifted by the change in electricity over the item's lifespan; for vehicles, by the change in yearly
    /// driving. Food and consumables need no change: their yearly view already scales with servings, packs or uses.
    public func applyingUsage(_ usage: UsageProfile, to component: Component, profile: UserProfile) -> Component {
        var updated = component
        updated.usage = usage
        if let vehicle = vehicleModel(for: component) {
            if let kWh = vehicle.yearlyElectricity(usage, seed: component.stableSeed) { updated.metrics[.yearlyElectricity] = kWh }
            let grid = gridGramsPerKWh(for: profile)
            let yearlyDelta = vehicle.drivingKgCO2e(kmPerYear: vehicle.kmPerYear(usage), gramsPerKWh: grid)
                - vehicle.drivingKgCO2e(kmPerYear: vehicle.kmPerYear(component.usage), gramsPerKWh: grid)
            return shiftingUsePhase(of: updated, from: component, byKg: yearlyDelta * lifespan(of: component).value)
        }
        guard component.category == .electronic,
              let newKWh = derivedYearlyElectricity(for: updated) else { return updated }
        let oldKWh = component.metrics[.yearlyElectricity]
        updated.metrics[.yearlyElectricity] = newKWh

        guard let oldKWh else { return updated }
        let lifespanYears = lifespan(of: component).value
        let deltaKg = Self.useCarbon(kWh: newKWh.value - oldKWh.value, gramsPerKWh: gridGramsPerKWh(for: profile)) * lifespanYears
        return shiftingUsePhase(of: updated, from: component, byKg: deltaKg)
    }

    /// `updated` with `component`'s carbon moved by `deltaKg` of use phase. The flow view stays consistent: the use
    /// stage grows or shrinks by the same amount.
    private func shiftingUsePhase(of updated: Component, from component: Component, byKg deltaKg: Double) -> Component {
        guard let carbon = component.metrics[.carbon] else { return updated }
        var result = updated
        let newValue = max(carbon.value + deltaKg, 0)
        result.metrics[.carbon] = Measured(value: newValue, low: max(carbon.low + deltaKg, 0), high: max(carbon.high + deltaKg, newValue),
                                           unit: carbon.unit, tier: carbon.tier, sources: carbon.sources)
        let shares = stageShares(for: component, metric: .carbon)
        var absolute = shares.mapValues { $0 * carbon.value }
        absolute[.use, default: 0] = max((absolute[.use] ?? 0) + deltaKg, 0)
        result.stageShares = StageModel.normalized(absolute)
        return result
    }

    /// Applies one question answer (`AnswerOption.field` = `value`); options without a field leave the estimate.
    /// Identify asks about food in servings, so for a per-pack item a servings-a-week answer sets packs a week.
    public func applyingAnswer(_ option: AnswerOption, to component: Component, profile: UserProfile) -> Component {
        guard var field = option.field, var value = option.value else { return component }
        if field == .servingsPerWeek, FoodServing.isPerPack(component) {
            field = .packsPerWeek
            value = FoodServing.packsPerWeek(servingsPerWeek: value, for: component)
        }
        return applyingUsage((component.usage ?? UsageProfile()).setting(field, to: value), to: component, profile: profile)
    }
}

extension ImpactEngine {
    /// Hours of active use one full charge covers for battery devices (phones, tablets, laptops), used to turn
    /// "hours a day" into charges per week.
    public static let activeHoursPerCharge = 6.0

    /// Battery capacity for the component's device type, when it is a battery device.
    public func batteryKWh(for component: Component) -> Double? {
        store?.deviceProfile(deviceType: component.quantities.deviceType ?? component.name)?.batteryKWh
    }

    /// The usage fields that drive this component's yearly numbers, with the value the engine uses now (the
    /// stored usage, else its default), so they can be edited even when no question was asked.
    public func editableUsage(for component: Component) -> [(field: UsageField, value: Double)] {
        let usage = component.usage
        switch component.category {
        case .electronic:
            let typical = store?.deviceProfile(deviceType: component.quantities.deviceType ?? component.name)?
                .defaults.typicalHoursOnPerDay ?? 4
            let hoursOn = usage?.hoursOnPerDay ?? typical
            return [(.hoursOnPerDay, hoursOn), (.standbyHoursPerDay, usage?.standbyHoursPerDay ?? max(0, 24 - hoursOn))]
        case .food where FoodServing.isPerPack(component):
            return [(.packsPerWeek, FoodServing.packsPerWeek(of: component))]
        case .food:
            return [(.servingsPerWeek, usage?.servingsPerWeek ?? FoodServing.defaultServingsPerWeek)]
        case .packaging, .personalCare:
            return [(.usesPerWeek, usage?.usesPerWeek ?? 1)]
        case .vehicle:
            let typicalKm = (vehicleModel(for: component)?.factors.kmPerYear ?? 0) / Self.weeksPerYear
            return typicalKm > 0 || usage?.kmPerWeek != nil ? [(.kmPerWeek, usage?.kmPerWeek ?? typicalKm)] : []
        case .clothing, .household:
            return []
        }
    }

    /// Answers that apply a usage edit. For battery devices, hours of use also set charges per week, since
    /// their electricity comes from charging.
    public func usageEdits(_ field: UsageField, _ value: Double, for component: Component) -> [AnswerOption] {
        var edits = [AnswerOption(label: field.rawValue, field: field, value: value)]
        if field == .hoursOnPerDay, batteryKWh(for: component) != nil {
            let charges = min(max(value * 7 / Self.activeHoursPerCharge, 0), 21)
            edits.append(AnswerOption(label: UsageField.chargesPerWeek.rawValue, field: .chargesPerWeek, value: charges))
        }
        return edits
    }
}
