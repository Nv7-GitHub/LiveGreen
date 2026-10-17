import Foundation

/// GreenScore: how much greener a swap is than the item it replaces, with every relevant metric weighted
/// equally, so a big carbon cut cannot hide a big rise in water, plastic or anything else.
///
/// Each metric's change is the log ratio ln(current / swap), flipped for metrics where higher is better
/// (lifespan, repairability, recyclable share), so better is positive for every metric, and halving a value
/// counts as much in its favor as doubling it counts against. A small floor per metric (`negligible`) is added to both sides,
/// so swings in amounts nobody would notice (0.3 W → 0.5 W standby) do not read as big changes, and each change
/// is clamped to ±ln 4 so one metric cannot outweigh the rest. The score is the plain mean of the changes, i.e.
/// the log of the geometric-mean improvement across metrics.
///
/// A metric is relevant when it applies to both categories, both sides have a value, and the two values are not
/// both negligible. Amounts are compared per year of doing the same job where they recur for the original
/// (`recursYearly`), so a reusable cup is set against a year of disposable ones; ratings, shares, power draw and
/// lifespan are compared as they are.
///
/// A swap is kept only when no relevant metric gets more than `maxWorsening` worse and the score shows a real
/// average gain (`minimumScore`). Smart-plug scheduling keeps the same device, so it is exempt and listed last.
public enum GreenScore {
    /// No relevant metric may get more than 40% worse (a factor of 1.4 on the log scale; for lifespan,
    /// repairability and recyclability that is a drop of more than ~29%).
    public static let maxWorsening = 0.4
    /// The swap must be at least 2% better on average (geometric mean) across its relevant metrics.
    public static let minimumScore = log(1.02)
    /// Largest change one metric can contribute, either way: 4× better or worse.
    public static let clampRatio = 4.0

    /// Amounts below which a metric is noise, in canonical units on the comparison basis (per year for
    /// recurring amounts).
    public static let negligible: [MetricKey: Double] = [
        .carbon: 0.1, .water: 1, .land: 0.01, .powerOn: 1, .standbyPower: 0.5, .yearlyElectricity: 1,
        .lifespan: 0.5, .repairability: 0.5, .plasticMass: 1, .recyclablePercent: 5, .decompositionTime: 0.5,
        .waterPollution: 0.5,
    ]

    /// Per-item amounts, which add up over items and years; the other metrics are ratings, shares, power draws
    /// and lifespan. Decomposition counts as an amount: each item thrown away lingers that long.
    public static let amounts: Set<MetricKey> = [.carbon, .water, .land, .plasticMass, .waterPollution, .decompositionTime]

    /// One swap's verdict.
    public struct Assessment: Sendable, Hashable {
        /// Mean change across relevant metrics; positive is greener.
        public var score: Double
        /// Change per relevant metric (log ratio, positive = better), before clamping.
        public var changes: [MetricKey: Double]

        /// The relevant metric that gets most worse, when any does.
        public var worstMetric: MetricKey? {
            changes.filter { $0.value < 0 }.min { $0.value < $1.value }?.key
        }

        /// No big trade-off on any metric and a real gain overall.
        public var isAcceptable: Bool {
            !changes.isEmpty && score >= GreenScore.minimumScore
                && changes.values.allSatisfy { $0 >= -log(1 + GreenScore.maxWorsening) }
        }

        /// Geometric-mean improvement as a fraction (0.25 = 25% better on average).
        public var averageImprovement: Double { 1 - exp(-score) }
    }

    // MARK: - Basis

    /// Whether a metric repeats every year for this component (§8). Carbon (amortized purchase plus use) and
    /// electricity always do; other amounts only for consumables bought over and over. For a durable item they
    /// are a one-time cost of making it.
    public static func recursYearly(_ metric: MetricKey, for component: Component, engine: ImpactEngine) -> Bool {
        if metric == .carbon || metric == .yearlyElectricity { return true }
        guard amounts.contains(metric), case .unitsPerYear = engine.annualBasis(for: component) else { return false }
        return true
    }

    /// Per-unit → yearly multiplier (`ImpactEngine.annualBasis`): consumables × units per year, durables ÷
    /// lifespan; yearly electricity is already yearly.
    public static func yearlyFactor(_ metric: MetricKey, for component: Component, engine: ImpactEngine) -> Double {
        if metric == .yearlyElectricity { return 1 }
        switch engine.annualBasis(for: component) {
        case .unitsPerYear(let units): return units
        case .lifetime(let lifespan): return lifespan.value > 0 ? 1 / lifespan.value : 1
        }
    }

    /// The two values a swap is judged and shown on: per year where the metric recurs for the original (each side
    /// annualized by its own category and lifespan), else as stored. `annualized` is false for values as stored,
    /// including yearly electricity, whose unit already says per year.
    public static func comparison(_ metric: MetricKey, original: Component, alternative: Alternative,
                                  engine: ImpactEngine) -> (current: Measured, swap: Measured, annualized: Bool)? {
        guard let current = original.metrics[metric], let swap = alternative.metrics[metric] else { return nil }
        guard metric != .yearlyElectricity, recursYearly(metric, for: original, engine: engine) else {
            return (current, swap, false)
        }
        let replacement = alternative.asComponent(replacing: original)
        return (current.scaled(by: yearlyFactor(metric, for: original, engine: engine)),
                swap.scaled(by: yearlyFactor(metric, for: replacement, engine: engine)), true)
    }

    // MARK: - Score

    /// Change of one metric, positive = better: ln((current + floor) / (swap + floor)), flipped when higher is better.
    public static func change(_ metric: MetricKey, current: Double, swap: Double) -> Double {
        let floor = negligible[metric] ?? 0
        let ratio = log((max(current, 0) + floor) / (max(swap, 0) + floor))
        guard ratio.isFinite else { return 0 }
        return metric.higherIsBetter ? -ratio : ratio
    }

    /// Metrics that count for this swap: applicable to both categories, valued on both sides, not both negligible.
    public static func relevantMetrics(original: Component, alternative: Alternative, engine: ImpactEngine) -> [MetricKey] {
        MetricKey.allCases.filter { metric in
            guard original.category.applies(metric), alternative.category.applies(metric),
                  let values = comparison(metric, original: original, alternative: alternative, engine: engine)
            else { return false }
            let floor = negligible[metric] ?? 0
            return abs(values.current.value) > floor || abs(values.swap.value) > floor
        }
    }

    public static func assess(_ alternative: Alternative, replacing original: Component,
                              engine: ImpactEngine = ImpactEngine()) -> Assessment {
        var changes: [MetricKey: Double] = [:]
        for metric in relevantMetrics(original: original, alternative: alternative, engine: engine) {
            guard let values = comparison(metric, original: original, alternative: alternative, engine: engine) else { continue }
            changes[metric] = change(metric, current: values.current.value, swap: values.swap.value)
        }
        let limit = log(clampRatio)
        let clamped = changes.values.map { min(max($0, -limit), limit) }
        let score = clamped.isEmpty ? 0 : clamped.reduce(0, +) / Double(clamped.count)
        return Assessment(score: score, changes: changes)
    }

    /// Drops product swaps with a big trade-off or no real gain and orders the rest by score, best first.
    /// Smart-plug scheduling (the same device, so nothing to score) stays, after the product swaps.
    public static func ranked(_ alternatives: [Alternative], replacing original: Component,
                              engine: ImpactEngine = ImpactEngine()) -> [Alternative] {
        let products = alternatives.filter { $0.kind == .product }
            .map { ($0, assess($0, replacing: original, engine: engine)) }
            .filter(\.1.isAcceptable)
            .sorted { $0.1.score > $1.1.score }
            .map(\.0)
        return products + alternatives.filter { $0.kind == .smartPlugScheduling }
    }

    /// Whether the swap belongs on screen: always for smart-plug scheduling, else when acceptable.
    public static func accepts(_ alternative: Alternative, replacing original: Component,
                               engine: ImpactEngine = ImpactEngine()) -> Bool {
        alternative.kind == .smartPlugScheduling || assess(alternative, replacing: original, engine: engine).isAcceptable
    }
}

extension Alternative {
    /// The alternative as a component, so it annualizes by its own category and lifespan; usage it does not state
    /// is the original's.
    public func asComponent(replacing original: Component) -> Component {
        Component(id: id, name: name, category: category, identifiers: identifiers, quantities: quantities,
                  metrics: metrics, usage: usage ?? original.usage)
    }
}
