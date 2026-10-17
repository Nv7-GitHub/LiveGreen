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

    static let engine = ImpactEngine()

    /// The two values a metric is compared and charted on (`GreenScore.comparison`): per year where it recurs for
    /// the original, else as stored, so the chart, its "% better" chip and the GreenScore filter agree. Nil when
    /// either side has no value or there is no net change to show.
    static func comparison(_ metric: MetricKey, _ component: Component,
                           _ alternative: Alternative) -> (current: Measured, swap: Measured, annualized: Bool)? {
        guard let values = GreenScore.comparison(metric, original: component, alternative: alternative, engine: engine),
              showsChange(metric, current: values.current, alternative: values.swap) else { return nil }
        return values
    }

    /// Up to `limit` metrics both sides have a value for and that change.
    static func keyMetrics(_ component: Component, _ alternative: Alternative, limit: Int = 4) -> [MetricKey] {
        Array(chartPriority.filter { comparison($0, component, alternative) != nil }.prefix(limit))
    }

    /// Improvement in percent (positive = the alternative is better), nil when the baseline is zero.
    static func percentBetter(_ metric: MetricKey, current: Measured, alternative: Measured) -> Double? {
        guard current.value != 0 else { return nil }
        let change = (alternative.value - current.value) / abs(current.value) * 100
        return metric.higherIsBetter ? change : -change
    }

    /// Whether a metric's change is worth a row: not when both sides are effectively zero ("0 g → 0 g") or the
    /// change rounds to 0% (no net change). Worse is always shown, including a rise from zero.
    static func showsChange(_ metric: MetricKey, current: Measured, alternative: Measured) -> Bool {
        guard displayable(current, metric) != nil || displayable(alternative, metric) != nil,
              current.value != alternative.value else { return false }
        guard let percent = percentBetter(metric, current: current, alternative: alternative) else { return true }
        return Int(percent.rounded()) != 0
    }

    /// The results screen's zero rule (GreenCore's `Component.displayable`): nil when a value and its range are
    /// effectively zero. A 0/10 repairability or 0% recyclable share is a real value, so those are kept.
    static func displayable(_ measured: Measured, _ metric: MetricKey) -> Measured? {
        if metric == .recyclablePercent || metric == .repairability { return measured }
        return max(abs(measured.low), abs(measured.value), abs(measured.high)) < 1e-3 ? nil : measured
    }

    /// Whether a saving is a net change: not effectively zero, and not rounding to 0% of `baseline` (what the
    /// item had on the same basis; zero means unknown).
    static func isNetChange(_ saving: EstimateRange, baseline: Double) -> Bool {
        guard max(abs(saving.low), abs(saving.value), abs(saving.high)) >= 1e-3 else { return false }
        guard baseline != 0 else { return saving.value != 0 }
        return Int((saving.value / abs(baseline) * 100).rounded()) != 0
    }

    /// Per-unit → yearly multiplier with the impact engine's conventions (`GreenScore.yearlyFactor`).
    static func yearlyFactor(_ metric: MetricKey, for component: Component) -> Double {
        GreenScore.yearlyFactor(metric, for: component, engine: engine)
    }

    /// The alternative as a component, so it annualizes by its own category and lifespan; usage it does not
    /// state is the original's.
    static func component(for alternative: Alternative, replacing component: Component) -> Component {
        alternative.asComponent(replacing: component)
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

    /// The default pick (spec §7): the product swap with the best GreenScore, so no single metric decides;
    /// smart-plug scheduling when it is the only option.
    static func defaultPick(for component: Component, among alternatives: [Alternative]) -> Alternative? {
        let products = alternatives.filter { $0.kind == .product }
        if let best = products.max(by: { score($0, component) < score($1, component) }) { return best }
        return alternatives.first { $0.kind == .smartPlugScheduling }
    }

    static func score(_ alternative: Alternative, _ component: Component) -> Double {
        GreenScore.assess(alternative, replacing: component, engine: engine).score
    }

    /// Whether a metric's impact repeats every year for this component (`GreenScore.recursYearly`): carbon and
    /// electricity always; water, land, plastic and pollution only for consumables bought over and over. For a
    /// durable item those are a one-time cost of making it.
    static func recursYearly(_ metric: MetricKey, for component: Component) -> Bool {
        GreenScore.recursYearly(metric, for: component, engine: engine)
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

    /// Sums the savings of every chosen swap: yearly for recurring impacts, once for the rest. Metrics no swap
    /// changes are left out.
    static func projectedSavings(_ result: ScanResult, selection: [UUID: UUID]) -> [MetricKey: SavingSplit] {
        var totals: [MetricKey: SavingSplit] = [:]
        for component in result.components {
            guard let pickID = selection[component.id],
                  let pick = component.alternatives.first(where: { $0.id == pickID }) else { continue }
            for metric in savingsMetrics {
                var split = totals[metric] ?? SavingSplit()
                // A swap that leaves this metric as it was adds no row (no "0 oz once").
                if recursYearly(metric, for: component) {
                    let baseline = (component.metrics[metric]?.value ?? 0) * yearlyFactor(metric, for: component)
                    guard let saving = yearlySaving(metric, component: component, alternative: pick),
                          isNetChange(saving, baseline: baseline) else { continue }
                    split.yearly = SavingSplit.adding(saving, to: split.yearly)
                } else {
                    guard let saving = oneTimeSaving(metric, component: component, alternative: pick),
                          isNetChange(saving, baseline: component.metrics[metric]?.value ?? 0) else { continue }
                    split.oneTime = SavingSplit.adding(saving, to: split.oneTime)
                }
                totals[metric] = split
            }
        }
        return totals
    }
}
