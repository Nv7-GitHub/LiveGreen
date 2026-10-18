import Foundation

/// What a component's per-year figures assume (spec §5.6): how often a consumable is eaten, bought or used, or how
/// long a durable lasts. Shown beside per-year values so the frequency behind them is never hidden.
public enum UsageAssumption: Sendable, Hashable {
    case servingsPerWeek(Double)
    case packsPerWeek(Double)
    case usesPerWeek(Double)
    case lifespan(years: Double)
}

extension ImpactEngine {
    /// The frequency or lifespan `annualBasis(for:)` turns the component's per-unit values into a year with.
    public func usageAssumption(for component: Component) -> UsageAssumption {
        switch annualBasis(for: component) {
        case .lifetime(let lifespan):
            return .lifespan(years: lifespan.value)
        case .unitsPerYear(let units):
            let perWeek = units / Self.weeksPerYear
            // A household consumable's year counts items used up; what it assumes is how often it is used.
            if component.category == .household { return .usesPerWeek(component.usage?.usesPerWeek ?? 1) }
            guard component.category == .food else { return .usesPerWeek(perWeek) }
            return FoodServing.isPerPack(component) ? .packsPerWeek(perWeek) : .servingsPerWeek(perWeek)
        }
    }
}

/// Per-item yearly figures for the results screen (spec §5.6). The headline is a yearly total, so every row, share,
/// rank and data-quality split uses the same basis: a laptop's whole life is never ranked against one serving of a
/// drink. Per-unit values (one serving, a durable's whole life) stay on the item, in its detail sheet.
public struct ScanBreakdown: Sendable {
    /// Each component's yearly value per additive metric (`ImpactEngine.annualized`), by component id.
    public let yearly: [UUID: [MetricKey: Measured]]
    /// Pin and row number per component id. Ranked once by yearly carbon (then detection order), so a number
    /// names the same item whichever metric is selected.
    public let numbers: [UUID: Int]
    /// Ids of durables: items whose per-unit values cover a whole life (`AnnualBasis.lifetime`).
    public let durables: Set<UUID>
    /// What each component's year assumes, by component id.
    public let assumptions: [UUID: UsageAssumption]

    public init(components: [Component], engine: ImpactEngine = ImpactEngine()) {
        var yearly: [UUID: [MetricKey: Measured]] = [:]
        var durables: Set<UUID> = []
        var assumptions: [UUID: UsageAssumption] = [:]
        for component in components {
            yearly[component.id] = engine.annualized(component)
            let assumption = engine.usageAssumption(for: component)
            assumptions[component.id] = assumption
            if case .lifespan = assumption { durables.insert(component.id) }
        }
        self.yearly = yearly
        self.durables = durables
        self.assumptions = assumptions

        let carbon = { (component: Component) in yearly[component.id]?[.carbon]?.value ?? -.infinity }
        let order = components.enumerated().sorted { lhs, rhs in
            let l = carbon(lhs.element), r = carbon(rhs.element)
            return l != r ? l > r : lhs.offset < rhs.offset
        }
        numbers = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1.element.id, $0 + 1) })
    }

    /// The component's yearly value for an additive metric, or nil when it has none.
    public func yearly(_ metric: MetricKey, of component: Component) -> Measured? {
        yearly[component.id]?[metric]
    }

    public func isDurable(_ component: Component) -> Bool { durables.contains(component.id) }

    /// Sum of yearly values (non-negative) across components.
    public func total(_ metric: MetricKey, in components: [Component]) -> Double {
        components.reduce(0) { $0 + max(0, yearly(metric, of: $1)?.value ?? 0) }
    }

    /// The component's share (0–1) of the components' yearly total; 0 when unknown.
    public func share(of component: Component, metric: MetricKey, in components: [Component]) -> Double {
        let sum = total(metric, in: components)
        guard sum > 0, let value = yearly(metric, of: component)?.value else { return 0 }
        return max(0, value) / sum
    }

    /// Components by yearly value, largest first; unknown values last; ties by number.
    public func ranked(_ components: [Component], by metric: MetricKey) -> [Component] {
        components.sorted { lhs, rhs in
            let l = yearly(metric, of: lhs)?.value ?? -.infinity
            let r = yearly(metric, of: rhs)?.value ?? -.infinity
            return l != r ? l > r : number(of: lhs) < number(of: rhs)
        }
    }

    public func number(of component: Component) -> Int { numbers[component.id] ?? Int.max }

    // MARK: Data quality

    /// Fraction of the metric's yearly total per evidence tier, in tier order, omitting empty tiers. Each item counts
    /// with its yearly value and the tier of its own value for the metric: the default lifespan a year divides by is
    /// not evidence about the item.
    public func tierShares(_ metric: MetricKey, in components: [Component]) -> [(tier: Tier, share: Double)] {
        let sum = total(metric, in: components)
        guard sum > 0 else { return [] }
        return Tier.allCases.compactMap { tier in
            let part = components
                .filter { $0.metrics[metric]?.tier == tier }
                .reduce(0) { $0 + max(0, yearly(metric, of: $1)?.value ?? 0) }
            return part > 0 ? (tier, part / sum) : nil
        }
    }

    /// Share of the yearly total resolved at T1 or T2 (spec §6 confidence).
    public func confidence(_ metric: MetricKey, in components: [Component]) -> Double {
        tierShares(metric, in: components).filter { $0.tier <= .researchedSpec }.reduce(0) { $0 + $1.share }
    }

    /// Share of the yearly total that rests on what the AI saw in the photo: typical values or estimates for items
    /// with no barcode record, whose type, size and food group are its guesses.
    public func photoGuessedShare(_ metric: MetricKey, in components: [Component]) -> Double {
        let sum = total(metric, in: components)
        guard sum > 0 else { return 0 }
        let guessed = components.filter { component in
            guard let tier = component.metrics[metric]?.tier, tier >= .factorModel else { return false }
            return component.identifiers.gtin?.isEmpty ?? true
        }
        return total(metric, in: guessed) / sum
    }

    // MARK: Per-unit totals

    /// Durables' whole-life total for the metric (one of each durable), or nil when no durable has it.
    public func lifetimeTotal(_ metric: MetricKey, in components: [Component], seed: UInt64) -> Measured? {
        unitTotal(metric, of: components.filter(isDurable), seed: seed, salt: "lifetime")
    }

    /// Consumables' total for one unit of each (one serving, pack or use), or nil when no consumable has the metric.
    public func consumablesTotal(_ metric: MetricKey, in components: [Component], seed: UInt64) -> Measured? {
        unitTotal(metric, of: components.filter { !isDurable($0) }, seed: seed, salt: "consumables")
    }

    /// One item's own value as is (its range is not resampled), else the Monte Carlo sum.
    private func unitTotal(_ metric: MetricKey, of components: [Component], seed: UInt64, salt: String) -> Measured? {
        let values = components.compactMap { $0.metrics[metric] }
        if values.count == 1 { return values[0] }
        return MonteCarlo(seed: seed).sum(values, salt: "\(salt).\(metric.rawValue)")
    }
}
