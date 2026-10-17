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
        case .food:
            return .unitsPerYear((usage?.servingsPerWeek ?? 1) * Self.weeksPerYear)
        case .packaging, .personalCare:
            return .unitsPerYear((usage?.usesPerWeek ?? 1) * Self.weeksPerYear)
        case .electronic, .clothing, .household:
            return .lifetime(lifespan: lifespan(of: component))
        }
    }

    /// The component's lifespan metric, else the reference default for its type, else 5 years (±40%).
    public func lifespan(of component: Component) -> Measured {
        if let measured = component.metrics[.lifespan], measured.value > 0 { return measured }
        if component.category == .clothing, let garment = store?.garment {
            return Measured(value: garment.lifespanYears, relativeRange: 0.4, unit: .years, tier: .factorModel,
                            sources: [garment.lifespanCitation])
        }
        if let defaults = reference.deviceDefaults(deviceType: component.quantities.deviceType ?? component.name) {
            return Measured(value: defaults.lifespanYears, relativeRange: 0.3, unit: .years, tier: .factorModel,
                            sources: [defaults.citation])
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

    /// Uncertainty-aware yearly totals across components (spec §5.6), one joint Monte Carlo per metric.
    public func yearlyTotals(_ components: [Component], seed: UInt64) -> [MetricKey: Measured] {
        Self.annualMetrics.reduce(into: [:]) { result, metric in
            result[metric] = yearlyTotal(metric, of: components, seed: seed)
        }
    }

    /// Uncertainty-aware per-unit totals (what is in the photo), one Monte Carlo per metric.
    public func itemTotals(_ components: [Component], seed: UInt64) -> [MetricKey: Measured] {
        let mc = MonteCarlo(seed: seed)
        return Self.annualMetrics.reduce(into: [:]) { result, metric in
            result[metric] = mc.sum(components.compactMap { $0.metrics[metric] }, salt: "items.\(metric.rawValue)")
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
        guard !terms.isEmpty else { return nil }
        return MonteCarlo(seed: seed).propagate(inputs, unit: metric.unit, salt: "yearly.\(metric.rawValue)") { draws in
            terms.reduce(0) { total, term in
                let value = draws[term.valueIndex] * term.multiplier
                guard let divisor = term.divisorIndex else { return total + value }
                return total + value / max(draws[divisor], 0.25)
            }
        }
    }
}
