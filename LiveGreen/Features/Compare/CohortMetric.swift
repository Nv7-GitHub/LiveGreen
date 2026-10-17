import Foundation
import GreenCore

/// The metrics the cohort compares (per-capita baselines exist only for these).
nonisolated enum CohortMetric {
    static let all: [MetricKey] = CohortModel.comparedMetrics

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
