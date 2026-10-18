import Foundation

/// Adjustments a swap needs beyond the evidence ladder, so it is compared with its original on the same footing:
/// washing for reusables and the production share of second-hand items.
extension ImpactEngine {
    /// Power and water for washing a reusable once: mostly a dishwasher load's share (~1 kWh and ~10 L for ~100
    /// items), sometimes a hot hand rinse (~0.02 kWh, ~0.5 L).
    public static let washKWhPerUse = 0.015
    public static let washLitersPerUse = 0.15

    /// The reusable with washing for `usesPerWeek` added to its lifetime carbon and water, over its lifespan; a
    /// negative rate takes washing off (when the usage it was resolved with goes down). Per use it is small, but a
    /// cup used daily is washed hundreds of times, so it usually outweighs making the cup.
    public func addingWashing(usesPerWeek: Double, to component: Component, profile: UserProfile) -> Component {
        guard usesPerWeek != 0 else { return component }
        let washes = usesPerWeek * Self.weeksPerYear * lifespan(of: component).value
        let carbon = washes * Self.useCarbon(kWh: Self.washKWhPerUse, gramsPerKWh: gridGramsPerKWh(for: profile))
        let note = Source(title: "Washing after each use (\(Self.washLitersPerUse) L and \(Self.washKWhPerUse) kWh of hot water)",
                          tier: .factorModel)
        var result = component
        result.metrics[.carbon] = component.metrics[.carbon].map { Self.adding(carbon, to: $0, note: note) }
        result.metrics[.water] = component.metrics[.water].map { Self.adding(washes * Self.washLitersPerUse, to: $0, note: note) }
        return result
    }

    /// The item bought second-hand: `share` of a new one's production impacts (embodied carbon, water, land, water
    /// pollution; `Alternative.Condition.productionShare`). An electronic device's carbon includes its use phase,
    /// which a second-hand device still has, so only the rest is discounted. Plastic, recyclability, power and
    /// lifespan are the item's own and stay.
    public func secondHand(_ component: Component, share: Double, profile: UserProfile) -> Component {
        let note = Source(title: "Bought second-hand: \(Int((share * 100).rounded()))% of a new one's production impacts",
                          tier: .estimate)
        var result = component
        for metric in [MetricKey.water, .land, .waterPollution] {
            result.metrics[metric] = component.metrics[metric].map { Self.noting(note, on: $0.scaled(by: share)) }
        }
        if let carbon = component.metrics[.carbon], carbon.value > 0 {
            var useKg = 0.0
            if component.category == .electronic, let kWh = component.metrics[.yearlyElectricity] {
                useKg = min(Self.useCarbon(kWh: kWh.value, gramsPerKWh: gridGramsPerKWh(for: profile))
                            * lifespan(of: component).value, carbon.value)
            }
            let factor = (useKg + (carbon.value - useKg) * share) / carbon.value
            result.metrics[.carbon] = Self.noting(note, on: carbon.scaled(by: factor))
        }
        return result
    }

    /// `measured` plus (or minus) an amount known to about ±50%, keeping its tier.
    private static func adding(_ amount: Double, to measured: Measured, note: Source) -> Measured {
        let (lowShare, highShare) = amount >= 0 ? (0.5, 1.5) : (1.5, 0.5)
        return Measured(value: max(measured.value + amount, 0), low: max(measured.low + amount * lowShare, 0),
                        high: max(measured.high + amount * highShare, 0), unit: measured.unit, tier: measured.tier,
                        sources: measured.sources + [note])
    }

    private static func noting(_ note: Source, on measured: Measured) -> Measured {
        Measured(value: measured.value, low: measured.low, high: measured.high, unit: measured.unit, tier: measured.tier,
                 sources: measured.sources + [note])
    }
}
