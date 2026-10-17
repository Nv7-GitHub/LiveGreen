/// Which metrics are worth showing for an item. One rule for every screen: a metric is shown only when it
/// applies to the item's category, has a value, and that value says something. "0 g plastic" on a wooden
/// spoon or "0 W standby" on a mug says nothing, so it is left off; 0% recyclable or 0/10 repairability is
/// real information and stays.
extension Measured {
    /// Below this, in the canonical unit, a value counts as zero (1 g CO2e, 1 mL, 1 mg, 1 mW…).
    public static let negligibleMagnitude = 1e-3

    /// True when the value and its whole range are ≈ 0.
    public var isEffectivelyZero: Bool {
        max(abs(low), abs(value), abs(high)) < Self.negligibleMagnitude
    }
}

extension MetricKey {
    /// Metrics where zero is meaningful (nothing recyclable, not repairable), so a zero is still shown.
    public var zeroIsInformative: Bool {
        switch self {
        case .recyclablePercent, .repairability: true
        default: false
        }
    }
}

extension Component {
    /// The value to show for `metric`, or nil when it does not apply, is missing, or is effectively zero
    /// for a metric where zero says nothing.
    public func displayable(_ metric: MetricKey) -> Measured? {
        guard category.applies(metric), let measured = metrics[metric] else { return nil }
        if measured.isEffectivelyZero, !metric.zeroIsInformative { return nil }
        return measured
    }

    /// Applicable metrics with a value worth showing, in display order.
    public var displayableMetrics: [MetricKey] {
        category.applicableMetrics.filter { displayable($0) != nil }
    }
}
