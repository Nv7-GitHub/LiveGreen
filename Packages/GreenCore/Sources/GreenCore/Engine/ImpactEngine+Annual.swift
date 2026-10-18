import Foundation

/// How a component's per-unit metrics turn into a year (see `ImpactEngine` for the conventions).
public enum AnnualBasis: Sendable, Hashable {
    /// Consumables: per-unit values × units per year.
    case unitsPerYear(Double)
    /// Durables: lifetime values ÷ lifespan.
    case lifetime(lifespan: Measured)
}

extension ImpactEngine {
    /// Metrics that annualize and add across components.
    public static var annualMetrics: [MetricKey] { ScanTotals.additiveMetrics }

    public func annualBasis(for component: Component) -> AnnualBasis {
        let usage = component.usage
        switch component.category {
        case .food where FoodServing.isPerPack(component):
            return .unitsPerYear(FoodServing.packsPerWeek(of: component) * Self.weeksPerYear)
        case .food:
            return .unitsPerYear((usage?.servingsPerWeek ?? FoodServing.defaultServingsPerWeek) * Self.weeksPerYear)
        case .packaging, .personalCare:
            return .unitsPerYear((usage?.usesPerWeek ?? 1) * Self.weeksPerYear)
        case .household where component.quantities.consumable == true:
            return .unitsPerYear(consumablesPerYear(of: component))
        case .electronic, .clothing, .household, .vehicle:
            return .lifetime(lifespan: lifespan(of: component))
        }
    }

    /// Uses one household consumable lasts when identify did not say.
    public static let defaultUsesPerContainer = 50.0

    /// How many uses one consumable lasts: identify's figure, else `defaultUsesPerContainer`.
    public func usesPerContainer(of component: Component) -> Double {
        component.quantities.usesPerContainer.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultUsesPerContainer
    }

    /// Household consumables used up a year: uses a week × 52 ÷ uses one lasts (a spray used 3 times a week, 80
    /// treatments a bottle, is about 2 bottles a year).
    public func consumablesPerYear(of component: Component) -> Double {
        (component.usage?.usesPerWeek ?? 1) * Self.weeksPerYear / usesPerContainer(of: component)
    }

    /// A household durable's service life by its kind or name; nil for consumables and other categories.
    func householdLifespan(of component: Component) -> HouseholdLifespan? {
        guard component.category == .household, component.quantities.consumable != true, let store else { return nil }
        return component.identifiers.genericKey.flatMap(store.householdLifespan(kind:))
            ?? store.householdLifespan(kind: component.name)
    }

    /// The component's lifespan metric, else the reference default for its type, else 5 years (±40%).
    public func lifespan(of component: Component) -> Measured {
        if let measured = component.metrics[.lifespan], measured.value > 0 { return measured }
        if component.category == .clothing, let garment = store?.garment {
            return Measured(value: garment.lifespanYears, relativeRange: 0.4, unit: .years, tier: .factorModel,
                            sources: [garment.lifespanCitation])
        }
        if let vehicle = vehicleModel(for: component) {
            return Measured(value: vehicle.factors.lifespanYears, relativeRange: 0.25, unit: .years, tier: .factorModel,
                            sources: [vehicle.factors.lifespanCitation])
        }
        if let defaults = component.deviceLookupKey.flatMap(reference.deviceDefaults(deviceType:)) {
            return Measured(value: defaults.lifespanYears, relativeRange: 0.3, unit: .years, tier: .factorModel,
                            sources: [defaults.citation])
        }
        if let household = householdLifespan(of: component) {
            return Measured(value: household.lifespanYears, relativeRange: 0.4, unit: .years, tier: .factorModel,
                            sources: [household.citation])
        }
        return Measured(value: Self.defaultLifespanYears, relativeRange: 0.4, unit: .years, tier: .estimate)
    }

    /// Yearly value of one metric for one component, or nil when the metric is missing or not additive.
    public func yearly(_ metric: MetricKey, of component: Component, seed: UInt64? = nil) -> Measured? {
        yearlyTotal(metric, of: [component], seed: seed ?? component.stableSeed)
    }

    /// Yearly impacts of one component for every additive metric it has.
    public func annualized(_ component: Component, seed: UInt64? = nil) -> [MetricKey: Measured] {
        let seed = seed ?? component.stableSeed
        return Self.annualMetrics.reduce(into: [:]) { result, metric in
            result[metric] = yearlyTotal(metric, of: [component], seed: seed)
        }
    }

    /// Uncertainty-aware yearly totals across components (spec §5.6), one joint Monte Carlo per metric. When only
    /// one component has the metric, its total is that component's own yearly figure (`yearly(_:of:)`, on its own
    /// seed), so the summary and the item's inspector never show two ranges for one item.
    public func yearlyTotals(_ components: [Component], seed: UInt64) -> [MetricKey: Measured] {
        Self.annualMetrics.reduce(into: [:]) { result, metric in
            let contributing = components.filter { $0.metrics[metric] != nil }
            result[metric] = contributing.count == 1 ? yearly(metric, of: contributing[0])
                                                     : yearlyTotal(metric, of: contributing, seed: seed)
        }
    }

    /// Uncertainty-aware per-unit totals (what is in the photo), one Monte Carlo per metric. A single value is its
    /// own total: resampling it would only add noise to its range.
    public func itemTotals(_ components: [Component], seed: UInt64) -> [MetricKey: Measured] {
        let mc = MonteCarlo(seed: seed)
        return Self.annualMetrics.reduce(into: [:]) { result, metric in
            let values = components.compactMap { $0.metrics[metric] }
            result[metric] = values.count == 1 ? values[0] : mc.sum(values, salt: "items.\(metric.rawValue)")
        }
    }

    /// Per-year and lifetime carbon for a durable; for consumables `lifetime` is nil and `perUnit` is one unit.
    public func carbonViews(of component: Component) -> (perUnit: Measured, perYear: Measured, lifetime: Measured?)? {
        guard let carbon = component.metrics[.carbon], let perYear = yearly(.carbon, of: component) else { return nil }
        if case .lifetime = annualBasis(for: component) { return (carbon, perYear, carbon) }
        return (carbon, perYear, nil)
    }

    private func yearlyTotal(_ metric: MetricKey, of components: [Component], seed: UInt64) -> Measured? {
        // Each term is value × multiplier, or value ÷ lifespan for durables; all sampled jointly.
        var inputs: [Measured] = []
        var terms: [(valueIndex: Int, divisorIndex: Int?, multiplier: Double)] = []
        for component in components {
            guard let value = component.metrics[metric] else { continue }
            inputs.append(value)
            let valueIndex = inputs.count - 1
            if metric == .yearlyElectricity {
                terms.append((valueIndex, nil, 1))
                continue
            }
            switch annualBasis(for: component) {
            case .unitsPerYear(let units):
                terms.append((valueIndex, nil, units))
            case .lifetime(let lifespan):
                inputs.append(lifespan)
                terms.append((valueIndex, inputs.count - 1, 1))
            }
        }
        guard let first = terms.first else { return nil }
        // One value times a count is exact; sampling it would only blur its own range.
        if terms.count == 1, first.divisorIndex == nil { return inputs[first.valueIndex].scaled(by: first.multiplier) }
        return MonteCarlo(seed: seed).propagate(inputs, unit: metric.unit, salt: "yearly.\(metric.rawValue)") { draws in
            terms.reduce(0) { total, term in
                let value = draws[term.valueIndex] * term.multiplier
                guard let divisor = term.divisorIndex else { return total + value }
                return total + value / max(draws[divisor], 0.25)
            }
        }
    }
}
