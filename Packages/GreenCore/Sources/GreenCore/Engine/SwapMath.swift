import Foundation

/// Like-for-like comparison math between a component and one of its alternatives (spec §7), shared by the swap
/// cards, their charts and the projected-savings card so all of them say the same thing.
public enum SwapMath {
    /// Every metric, most meaningful first: the cards show each one a swap changes, charts for the first
    /// `chartLimit` and a line each for the rest, so nothing the card counts is hidden.
    public static let chartPriority: [MetricKey] = [.carbon, .yearlyElectricity, .water, .land, .plasticMass,
                                                    .waterPollution, .powerOn, .standbyPower, .lifespan,
                                                    .repairability, .recyclablePercent, .decompositionTime]

    /// Metrics drawn as bar charts; the rest of a swap's changes are listed in one line each.
    public static let chartLimit = 4

    /// Metrics summed in the projected-savings card.
    public static let savingsMetrics: [MetricKey] = [.carbon, .yearlyElectricity, .water, .plasticMass]

    public static let engine = ImpactEngine()

    /// The two values a metric is compared and charted on (`GreenScore.comparison`): per year where it recurs for
    /// the original, else as stored, so the chart, its chip and the GreenScore filter agree. Nil when either side
    /// has no value or there is no net change to show.
    public static func comparison(_ metric: MetricKey, _ component: Component,
                                  _ alternative: Alternative) -> (current: Measured, swap: Measured, annualized: Bool)? {
        guard let values = GreenScore.comparison(metric, original: component, alternative: alternative, engine: engine),
              showsChange(metric, current: values.current, alternative: values.swap) else { return nil }
        return values
    }

    /// Every metric both sides have a value for and that changes, in chart order: what the card shows and counts.
    public static func shownMetrics(_ component: Component, _ alternative: Alternative) -> [MetricKey] {
        chartPriority.filter { comparison($0, component, alternative) != nil }
    }

    /// The shown metrics that get a bar chart.
    public static func keyMetrics(_ component: Component, _ alternative: Alternative) -> [MetricKey] {
        Array(shownMetrics(component, alternative).prefix(chartLimit))
    }

    // MARK: How a change reads

    /// One metric's change as its chip reads it.
    public struct MetricChange: Sendable, Hashable {
        public var isBetter: Bool
        /// "64% better", ">99% better", "+87 pts", "12× worse", or "Worse" for a rise from zero.
        public var label: String
    }

    /// How a metric's change reads, nil when it would round to nothing. A share or a 0–10 score changes by points
    /// (2.7% → 90% recyclable is "+87 pts", not "3,233% better"); other metrics by percent, where "100% better"
    /// means the swap's value is truly zero (else ">99% better") and anything 10× or more worse reads as a multiple.
    public static func change(_ metric: MetricKey, current: Measured, alternative: Measured) -> MetricChange? {
        guard current.value != alternative.value else { return nil }
        let sign = metric.higherIsBetter ? 1.0 : -1.0
        if metric.unit == .percent || metric.unit == .score10 {
            let points = (alternative.value - current.value) * sign
            let rounded = metric.unit == .percent ? points.rounded() : (points * 10).rounded() / 10
            guard rounded != 0 else { return nil }
            let magnitude = abs(rounded)
            let text = magnitude == magnitude.rounded() ? String(Int(magnitude)) : String(format: "%.1f", magnitude)
            return MetricChange(isBetter: rounded > 0, label: "\(rounded > 0 ? "+" : "−")\(text) pts")
        }
        guard current.value != 0 else {
            // Up from zero: no percentage, only the direction.
            let better = (alternative.value > 0) == metric.higherIsBetter
            return MetricChange(isBetter: better, label: better ? "Better" : "Worse")
        }
        let percent = (alternative.value - current.value) / abs(current.value) * 100 * sign
        let rounded = Int(percent.rounded())
        guard rounded != 0 else { return nil }
        if percent > 0 {
            let reachesZero = !metric.higherIsBetter && alternative.value <= 0
            return MetricChange(isBetter: true, label: rounded >= 100 && !metric.higherIsBetter && !reachesZero
                                ? ">99% better" : "\(rounded)% better")
        }
        let worse = metric.higherIsBetter ? current.value / alternative.value : alternative.value / current.value
        if worse.isFinite, worse >= 10 {
            return MetricChange(isBetter: false, label: "\(Int(worse.rounded()))× worse")
        }
        return MetricChange(isBetter: false, label: "\(-rounded)% worse")
    }

    /// Whether a metric's change is worth showing: not when both sides are effectively zero ("0 g → 0 g") or the
    /// change rounds to nothing. Worse is always shown, including a rise from zero.
    public static func showsChange(_ metric: MetricKey, current: Measured, alternative: Measured) -> Bool {
        let says = { (measured: Measured) in !measured.isEffectivelyZero || metric.zeroIsInformative }
        guard says(current) || says(alternative) else { return false }
        return change(metric, current: current, alternative: alternative) != nil
    }

    /// How many of the shown metrics get better and worse.
    public struct Tally: Sendable, Hashable {
        public var better: Int
        public var worse: Int
        public var total: Int { better + worse }
    }

    /// The card's headline count, from exactly the metrics it shows, so it can never disagree with its charts.
    public static func tally(_ component: Component, _ alternative: Alternative) -> Tally {
        var tally = Tally(better: 0, worse: 0)
        for metric in shownMetrics(component, alternative) {
            guard let values = comparison(metric, component, alternative),
                  let change = change(metric, current: values.current, alternative: values.swap) else { continue }
            if change.isBetter { tally.better += 1 } else { tally.worse += 1 }
        }
        return tally
    }

    // MARK: Savings

    /// Whether a saving is a net change: not effectively zero, and not rounding to 0% of `baseline` (what the
    /// item had on the same basis; zero means unknown).
    public static func isNetChange(_ saving: EstimateRange, baseline: Double) -> Bool {
        guard max(abs(saving.low), abs(saving.value), abs(saving.high)) >= Measured.negligibleMagnitude else { return false }
        guard baseline != 0 else { return saving.value != 0 }
        return Int((saving.value / abs(baseline) * 100).rounded()) != 0
    }

    /// Per-unit → yearly multiplier with the impact engine's conventions (`GreenScore.yearlyFactor`).
    public static func yearlyFactor(_ metric: MetricKey, for component: Component) -> Double {
        GreenScore.yearlyFactor(metric, for: component, engine: engine)
    }

    /// The component's carbon per year (consumables × units a year, durables ÷ lifespan): the basis the swap
    /// charts and savings use, so a card's header matches the rows under it.
    public static func yearlyCarbon(of component: Component) -> Measured? {
        component.metrics[.carbon].map { $0.scaled(by: yearlyFactor(.carbon, for: component)) }
    }

    /// Whether the item is kept for years (amortized over its lifespan) rather than bought again and again.
    public static func isDurable(_ component: Component) -> Bool {
        GreenScore.isDurable(component, engine: engine)
    }

    /// The alternative as a component, so it annualizes by its own category and lifespan; usage it does not
    /// state is the original's.
    public static func component(for alternative: Alternative, replacing component: Component) -> Component {
        alternative.asComponent(replacing: component)
    }

    /// Yearly saving of an additive metric (positive = less impact), with a range assuming correlated errors.
    public static func yearlySaving(_ metric: MetricKey, component: Component, alternative: Alternative) -> EstimateRange? {
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

    // MARK: Picks and order

    /// The default pick (spec §7): the product swap with the best GreenScore, so no single metric decides, among
    /// those that do not raise carbon, so the app never picks a swap that adds carbon for the user; smart-plug
    /// scheduling, which only cuts carbon, when no product qualifies. Nil keeps the original.
    public static func defaultPick(for component: Component, among alternatives: [Alternative]) -> Alternative? {
        let products = alternatives.filter { $0.kind == .product && !raisesCarbon(component, $0) }
        if let best = products.max(by: { score($0, component) < score($1, component) }) { return best }
        return alternatives.first { $0.kind == .smartPlugScheduling }
    }

    /// Whether the swap's yearly carbon is higher by a change its chart shows.
    public static func raisesCarbon(_ component: Component, _ alternative: Alternative) -> Bool {
        guard alternative.kind == .product, let values = comparison(.carbon, component, alternative),
              let change = change(.carbon, current: values.current, alternative: values.swap) else { return false }
        return !change.isBetter
    }

    public static func score(_ alternative: Alternative, _ component: Component) -> Double {
        GreenScore.assess(alternative, replacing: component, engine: engine).score
    }

    /// Components in swap-card order: the largest yearly carbon saving any offered swap makes first, so the swap
    /// that matters most leads; ties, and items whose swaps save no carbon, keep the scan's order after them.
    public static func byYearlySaving(_ components: [Component],
                                      options: (Component) -> [Alternative]) -> [Component] {
        let ranked = components.enumerated().map { index, component in
            (index: index, component: component,
             saving: options(component).compactMap { yearlySaving(.carbon, component: component, alternative: $0)?.value }
                .max() ?? -.infinity)
        }
        return ranked.sorted { $0.saving != $1.saving ? $0.saving > $1.saving : $0.index < $1.index }.map(\.component)
    }

    // MARK: Projected savings

    /// Whether a metric's impact repeats every year for this component (`GreenScore.recursYearly`): carbon and
    /// electricity always; water, land, plastic and pollution only for consumables bought over and over. For a
    /// durable item those are a one-time cost of making it.
    public static func recursYearly(_ metric: MetricKey, for component: Component) -> Bool {
        GreenScore.recursYearly(metric, for: component, engine: engine)
    }

    /// One-time saving per item (positive = less impact), for metrics that do not recur.
    public static func oneTimeSaving(_ metric: MetricKey, component: Component, alternative: Alternative) -> EstimateRange? {
        guard let current = component.metrics[metric], let swapped = alternative.metrics[metric] else { return nil }
        let value = current.value - swapped.value
        let a = current.low - swapped.low, b = current.high - swapped.high
        return EstimateRange(value: value, low: min(a, b, value), high: max(a, b, value))
    }

    /// A metric's savings across swaps, split into what repeats every year and what is saved once.
    public struct SavingSplit: Hashable, Sendable {
        public var yearly: EstimateRange?
        public var oneTime: EstimateRange?

        public init(yearly: EstimateRange? = nil, oneTime: EstimateRange? = nil) {
            self.yearly = yearly
            self.oneTime = oneTime
        }

        public static func adding(_ range: EstimateRange, to sum: EstimateRange?) -> EstimateRange {
            let sum = sum ?? EstimateRange(value: 0, low: 0, high: 0)
            return EstimateRange(value: sum.value + range.value, low: sum.low + range.low, high: sum.high + range.high)
        }
    }

    /// Sums the savings of every chosen swap: yearly for recurring impacts, once for the rest. Metrics no swap
    /// changes are left out.
    public static func projectedSavings(_ result: ScanResult, selection: [UUID: UUID]) -> [MetricKey: SavingSplit] {
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
