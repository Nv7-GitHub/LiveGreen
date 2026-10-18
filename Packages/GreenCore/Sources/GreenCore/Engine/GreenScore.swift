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
/// lifespan are compared as they are. Decomposition time is a property of one item, so it is compared per item,
/// only between items of the same kind (both single-use or both durable), capped at `decompositionCapYears`.
///
/// A swap is kept only when no relevant metric except decomposition gets more than `maxWorsening` worse, the score
/// shows a real average gain (`minimumScore`), and a food swap is a real change (`isRelabelledFood`). Smart-plug
/// scheduling keeps the same device, so it is exempt and listed last.
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

    /// Per-item amounts, which add up over items and years; the other metrics are ratings, shares, power draws,
    /// lifespan and decomposition time. Decomposition is how long one item lingers, not an amount: a year of PET
    /// cups is not 52 × 450 years, and how much is thrown away is what plastic mass counts.
    public static let amounts: Set<MetricKey> = [.carbon, .water, .land, .plasticMass, .waterPollution]

    /// Decomposition beyond this reads as "lasts" either way: plastics sit at 450–500 years, and glass's million
    /// years is an inert material, not a worse pollutant.
    public static let decompositionCapYears = 500.0

    /// Metrics that count toward the score but never veto a swap: decomposition per item says little next to the
    /// plastic and recyclability it comes with.
    public static let vetoExempt: Set<MetricKey> = [.decompositionTime]

    /// One swap's verdict.
    public struct Assessment: Sendable, Hashable {
        /// Mean change across relevant metrics; positive is greener.
        public var score: Double
        /// Change per relevant metric (log ratio, positive = better), before clamping.
        public var changes: [MetricKey: Double]
        /// A food swap that is the original food under another name (`GreenScore.isRelabelledFood`).
        public var isRelabelledFood = false

        /// The relevant metric that gets most worse, when any does.
        public var worstMetric: MetricKey? {
            changes.filter { $0.value < 0 }.min { $0.value < $1.value }?.key
        }

        /// No big trade-off on any metric that can veto, a real gain overall, and a real change.
        public var isAcceptable: Bool {
            !changes.isEmpty && !isRelabelledFood && score >= GreenScore.minimumScore
                && changes.allSatisfy { GreenScore.vetoExempt.contains($0.key) || $0.value >= -log(1 + GreenScore.maxWorsening) }
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
    /// including yearly electricity, whose unit already says per year. Nil when either side has no value, and for
    /// decomposition between a reusable and the single-use items it replaces, where one item's lifetime against
    /// another's says nothing about how much lingers.
    public static func comparison(_ metric: MetricKey, original: Component, alternative: Alternative,
                                  engine: ImpactEngine) -> (current: Measured, swap: Measured, annualized: Bool)? {
        guard let current = original.metrics[metric], let swap = alternative.metrics[metric] else { return nil }
        let replacement = alternative.asComponent(replacing: original)
        if metric == .decompositionTime,
           isDurable(original, engine: engine) != isDurable(replacement, engine: engine) { return nil }
        guard metric != .yearlyElectricity, recursYearly(metric, for: original, engine: engine) else {
            return (current, swap, false)
        }
        return (current.scaled(by: yearlyFactor(metric, for: original, engine: engine)),
                swap.scaled(by: yearlyFactor(metric, for: replacement, engine: engine)), true)
    }

    /// Kept for years (amortized over its lifespan) rather than used up.
    static func isDurable(_ component: Component, engine: ImpactEngine) -> Bool {
        if case .lifetime = engine.annualBasis(for: component) { return true }
        return false
    }

    /// Whether a food swap is the original food under another name ("local", "organic", "home-made", "brown"): the
    /// same food group, no smaller serving and no less packaging. Its factors are the original's, so any gap
    /// between the two would only be a gap between evidence tiers, not a greener choice.
    public static func isRelabelledFood(_ alternative: Alternative, replacing original: Component,
                                        engine: ImpactEngine) -> Bool {
        guard original.category == .food, alternative.category == .food,
              let originalGroup = canonicalFoodGroup(original.quantities.foodGroup, engine: engine),
              canonicalFoodGroup(alternative.quantities.foodGroup, engine: engine) == originalGroup else { return false }
        let replacement = alternative.asComponent(replacing: original)
        func isClearlySmaller(_ swap: Double?, than current: Double?) -> Bool {
            guard let swap, let current, current > 0 else { return false }
            return swap < current * 0.9
        }
        let smallerServing = isClearlySmaller(FoodServing.unitKg(replacement), than: FoodServing.unitKg(original))
        let lessPackaging = isClearlySmaller(replacement.quantities.packagingMassG ?? 0, than: original.quantities.packagingMassG)
        return !smallerServing && !lessPackaging
    }

    /// The reference group a food-group key or alias names ("lentils" → "other_pulses"), else the key lowercased.
    static func canonicalFoodGroup(_ key: String?, engine: ImpactEngine) -> String? {
        guard let key = key?.trimmingCharacters(in: .whitespaces).lowercased(), !key.isEmpty else { return nil }
        return engine.reference.foodFactor(group: key)?.group ?? key
    }

    // MARK: - Score

    /// Change of one metric, positive = better: ln((current + floor) / (swap + floor)), flipped when higher is better.
    /// Decomposition times are capped first (`decompositionCapYears`).
    public static func change(_ metric: MetricKey, current: Double, swap: Double) -> Double {
        let floor = negligible[metric] ?? 0
        let cap = metric == .decompositionTime ? decompositionCapYears : .infinity
        let ratio = log((min(max(current, 0), cap) + floor) / (min(max(swap, 0), cap) + floor))
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
        return Assessment(score: score, changes: changes,
                          isRelabelledFood: isRelabelledFood(alternative, replacing: original, engine: engine))
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
