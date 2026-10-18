import Foundation
import GreenCore

/// The metrics on the leaderboard: whole yearly footprints a profile can be placed against.
nonisolated enum CohortMetric {
    static let all: [MetricKey] = CohortModel.leaderboardMetrics

    /// What one number on the board stands for.
    static func basis(_ metric: MetricKey) -> String {
        switch metric {
        case .yearlyElectricity: "Yearly home electricity"
        case .water: "Yearly water use"
        case .land: "Yearly land use"
        default: "Whole yearly footprint"
        }
    }

    /// Whose numbers the peers are: the land baseline is one world farmland average, the rest are regional.
    static func peers(_ metric: MetricKey) -> String {
        metric == .land ? "worldwide" : "in your region"
    }

    /// Source of the per-capita figure behind `metric`, as cited in `per_capita.json`. Nil for carbon, whose
    /// source is the baseline's own citation.
    static func baselineSource(_ metric: MetricKey) -> String? {
        switch metric {
        case .water: "Our World in Data / FAO AQUASTAT, Water withdrawals per capita"
        case .land: "Our World in Data / FAO, Agricultural land per capita (world average)"
        case .yearlyElectricity: "Our World in Data / Ember, Per capita electricity demand"
        default: nil
        }
    }

    static func shortName(_ metric: MetricKey) -> String {
        switch metric {
        case .yearlyElectricity: "Electricity"
        default: metric.displayName
        }
    }
}

/// Formats a 0–1 share as a whole percent, saturating at the tails ("<1%", ">99%") so a footprint far
/// outside the cohort never reads as an exact 0% or 100%.
nonisolated enum SharePercent {
    static func format(_ share: Double) -> String {
        let percent = share * 100
        if percent >= 99.5 { return ">99%" }
        if percent < 0.5 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }
}
