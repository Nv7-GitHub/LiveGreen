import Foundation
import GreenCore

/// Like-for-like comparison math between a component and one of its alternatives (spec §7).
nonisolated enum SwapMath {
    /// Metrics shown in the comparison chart, most meaningful first.
    static let chartPriority: [MetricKey] = [.carbon, .yearlyElectricity, .water, .land, .plasticMass,
                                             .waterPollution, .standbyPower, .lifespan, .repairability,
                                             .recyclablePercent]

    /// Metrics summed in the projected-savings card.
    static let savingsMetrics: [MetricKey] = [.carbon, .yearlyElectricity, .water, .plasticMass]

    /// Up to `limit` metrics both sides have a value for.
    static func keyMetrics(_ component: Component, _ alternative: Alternative, limit: Int = 4) -> [MetricKey] {
        Array(chartPriority.filter { component.metrics[$0] != nil && alternative.metrics[$0] != nil }.prefix(limit))
    }

    /// Improvement in percent (positive = the alternative is better), nil when the baseline is zero.
    static func percentBetter(_ metric: MetricKey, current: Measured, alternative: Measured) -> Double? {
        guard current.value != 0 else { return nil }
        let change = (alternative.value - current.value) / abs(current.value) * 100
        return metric.higherIsBetter ? change : -change
    }

    static let engine = ImpactEngine()

    /// Per-unit → yearly multiplier with the impact engine's conventions (`ImpactEngine.annualBasis`):
    /// consumables × units per year, durables ÷ lifespan; yearly electricity is already yearly.
    static func yearlyFactor(_ metric: MetricKey, for component: Component) -> Double {
        if metric == .yearlyElectricity { return 1 }
        switch engine.annualBasis(for: component) {
        case .unitsPerYear(let units): return units
        case .lifetime(let lifespan): return lifespan.value > 0 ? 1 / lifespan.value : 1
        }
    }

    /// The alternative as a component, so it annualizes by its own category and lifespan; usage it does not
    /// state is the original's.
    static func component(for alternative: Alternative, replacing component: Component) -> Component {
        Component(id: alternative.id, name: alternative.name, category: alternative.category,
                  identifiers: alternative.identifiers, quantities: alternative.quantities,
                  metrics: alternative.metrics, usage: alternative.usage ?? component.usage)
    }

    /// Yearly saving of an additive metric (positive = less impact), with a range assuming correlated errors.
    static func yearlySaving(_ metric: MetricKey, component: Component, alternative: Alternative) -> EstimateRange? {
        if alternative.kind == .smartPlugScheduling, metric == .carbon {
            // Scheduling shifts charging to clean hours; the saving is the plug candidate's estimate.
            guard let savings = component.plugCandidate?.estimatedSavings else { return nil }
            return EstimateRange(value: savings.value, low: savings.low, high: savings.high)
        }
        guard let current = component.metrics[metric], let swapped = alternative.metrics[metric] else { return nil }
        let before = yearlyFactor(metric, for: component)
        let after = yearlyFactor(metric, for: Self.component(for: alternative, replacing: component))
        let value = current.value * before - swapped.value * after
        let a = current.low * before - swapped.low * after
        let b = current.high * before - swapped.high * after
        return EstimateRange(value: value, low: min(a, b, value), high: max(a, b, value))
    }

    /// The alternative with the biggest yearly carbon saving (spec §7 default pick).
    static func defaultPick(for component: Component, among alternatives: [Alternative]) -> Alternative? {
        alternatives.max { lhs, rhs in
            (yearlySaving(.carbon, component: component, alternative: lhs)?.value ?? -.infinity)
                < (yearlySaving(.carbon, component: component, alternative: rhs)?.value ?? -.infinity)
        }
    }

    /// Whether a metric's impact repeats every year for this component. Carbon (amortized purchase plus
    /// use) and electricity always do; water, land, plastic and pollution only for consumables bought over
    /// and over. For a durable item those are a one-time cost of making it.
    static func recursYearly(_ metric: MetricKey, for component: Component) -> Bool {
        if metric == .carbon || metric == .yearlyElectricity { return true }
        if case .unitsPerYear = engine.annualBasis(for: component) { return true }
        return false
    }

    /// One-time saving per item (positive = less impact), for metrics that do not recur.
    static func oneTimeSaving(_ metric: MetricKey, component: Component, alternative: Alternative) -> EstimateRange? {
        guard let current = component.metrics[metric], let swapped = alternative.metrics[metric] else { return nil }
        let value = current.value - swapped.value
        let a = current.low - swapped.low, b = current.high - swapped.high
        return EstimateRange(value: value, low: min(a, b, value), high: max(a, b, value))
    }

    /// A metric's savings across swaps, split into what repeats every year and what is saved once.
    struct SavingSplit: Hashable {
        var yearly: EstimateRange?
        var oneTime: EstimateRange?

        static func adding(_ range: EstimateRange, to sum: EstimateRange?) -> EstimateRange {
            let sum = sum ?? EstimateRange(value: 0, low: 0, high: 0)
            return EstimateRange(value: sum.value + range.value, low: sum.low + range.low, high: sum.high + range.high)
        }
    }

    /// Sums the savings of every chosen swap: yearly for recurring impacts, once for the rest.
    static func projectedSavings(_ result: ScanResult, selection: [UUID: UUID]) -> [MetricKey: SavingSplit] {
        var totals: [MetricKey: SavingSplit] = [:]
        for component in result.components {
            guard let pickID = selection[component.id],
                  let pick = component.alternatives.first(where: { $0.id == pickID }) else { continue }
            for metric in savingsMetrics {
                var split = totals[metric] ?? SavingSplit()
                if recursYearly(metric, for: component) {
                    guard let saving = yearlySaving(metric, component: component, alternative: pick) else { continue }
                    split.yearly = SavingSplit.adding(saving, to: split.yearly)
                } else {
                    guard let saving = oneTimeSaving(metric, component: component, alternative: pick) else { continue }
                    split.oneTime = SavingSplit.adding(saving, to: split.oneTime)
                }
                totals[metric] = split
            }
        }
        return totals
    }
}
