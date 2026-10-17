import Foundation
import GreenCore

/// The cohort contract the Compare tab renders (spec §9). `LocalCohortModel` implements it today;
/// GreenCore's `CohortModel` can be bound to it with a thin conformance at integration.
protocol CohortComparing {
    /// The peer distribution for a cohort metric, already scoped to the user's scanned categories.
    func distribution(for metric: MetricKey) -> LognormalDistribution?
    /// Lognormal CDF of `value` in the peer distribution: the share (0–1) of peers with a smaller footprint.
    func percentile(for metric: MetricKey, value: Double) -> Double
    /// The seeded, simulated peer network.
    func friends() -> [CohortFriend]
}

extension CohortComparing {
    /// "Greener than X% of people like you": the share (0–1) of peers with a larger footprint.
    func greenerThan(for metric: MetricKey, value: Double) -> Double {
        1 - percentile(for: metric, value: value)
    }
}

/// The metrics the cohort compares (per-capita baselines exist only for these).
enum CohortMetric {
    static let all: [MetricKey] = [.carbon, .water, .land, .yearlyElectricity]

    static func shortName(_ metric: MetricKey) -> String {
        switch metric {
        case .yearlyElectricity: "Electricity"
        default: metric.displayName
        }
    }
}

/// Formats a 0–1 share as a whole percent, saturating at the tails ("<1%", ">99%") so a footprint far
/// outside the cohort never reads as an exact 0% or 100%.
enum SharePercent {
    static func format(_ share: Double) -> String {
        let percent = share * 100
        if percent >= 99.5 { return ">99%" }
        if percent < 0.5 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }
}

/// A seeded member of the simulated peer network.
struct CohortFriend: Identifiable, Hashable {
    let id: Int
    let name: String
    let avatarSymbol: String
    /// Yearly footprint per cohort metric, in the metric's canonical unit.
    let footprints: [MetricKey: Double]
}
