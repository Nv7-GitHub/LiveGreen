import GreenCore

/// Approximate share of a person's yearly footprint that each product category accounts for, per metric.
/// Used to scope the per-capita baseline to the categories the user has actually scanned (spec §9:
/// compare category sub-footprints, not whole-life footprints). Shares follow the household-consumption
/// breakdowns in Ivanova et al. (2016), Journal of Industrial Ecology.
enum CategoryScope {
    static func share(of category: GreenCore.Category, for metric: MetricKey) -> Double {
        switch metric {
        case .carbon:
            switch category {
            case .food: 0.20
            case .electronic: 0.04
            case .clothing: 0.04
            case .packaging: 0.02
            case .household: 0.10
            case .personalCare: 0.02
            }
        case .water:
            switch category {
            case .food: 0.70
            case .electronic: 0.01
            case .clothing: 0.10
            case .packaging: 0.01
            case .household: 0.05
            case .personalCare: 0.03
            }
        case .land:
            switch category {
            case .food: 0.75
            case .electronic: 0.01
            case .clothing: 0.08
            case .packaging: 0.03
            case .household: 0.05
            case .personalCare: 0.02
            }
        case .yearlyElectricity:
            switch category {
            case .electronic: 0.35
            case .household: 0.45
            default: 0
            }
        default:
            0
        }
    }

    /// Combined share for a set of scanned categories, capped at the whole footprint.
    static func share(of categories: Set<GreenCore.Category>, for metric: MetricKey) -> Double {
        min(1, categories.reduce(0) { $0 + share(of: $1, for: metric) })
    }
}
