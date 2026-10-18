import Foundation
import GreenCore

/// Everything the Leaderboard tab shows, derived from saved scans, plug schedules, the profile and the bundled
/// reference tables through GreenCore's `CohortModel` (spec §9). Built off the main actor once per change of scans,
/// plugs or profile, with every board ready, so switching metrics is only a lookup.
nonisolated struct CompareAnalysis: Sendable {
    let footprint: ScannedFootprint
    /// Nil when there is no per-capita baseline for the profile's region.
    let cohort: CohortModel?
    let comparisons: [MetricKey: CohortComparison]
    let leaderboards: [MetricKey: [LeaderboardEntry]]
    /// You and your friends by GreenScore across every metric, greenest first.
    let overall: [OverallEntry]

    static let empty = CompareAnalysis(footprint: .empty, cohort: nil, comparisons: [:], leaderboards: [:], overall: [])

    init(footprint: ScannedFootprint, cohort: CohortModel?, comparisons: [MetricKey: CohortComparison],
         leaderboards: [MetricKey: [LeaderboardEntry]], overall: [OverallEntry]) {
        self.footprint = footprint
        self.cohort = cohort
        self.comparisons = comparisons
        self.leaderboards = leaderboards
        self.overall = overall
    }

    /// `plugSavingsKg` is what paired plugs' green-hours schedules avoid a year; it comes off your carbon.
    init(scans: [ScanResult], profile: UserProfile, plugSavingsKg: Double = 0, userName: String = "You",
         store: ReferenceStore = .bundled) {
        let engine = ImpactEngine(reference: store)
        let footprint = ScannedFootprint.from(scans: scans, scheduledSavingsKg: plugSavingsKg, engine: engine)
        let cohort = CohortModel(profile: profile, store: store)
        var comparisons: [MetricKey: CohortComparison] = [:]
        var leaderboards: [MetricKey: [LeaderboardEntry]] = [:]
        if let cohort {
            for comparison in cohort.compare(footprint) { comparisons[comparison.metric] = comparison }
            for metric in CohortMetric.all { leaderboards[metric] = cohort.leaderboard(for: footprint, metric: metric, userName: userName) }
        }
        self.init(footprint: footprint, cohort: cohort, comparisons: comparisons, leaderboards: leaderboards,
                  overall: cohort?.overallLeaderboard(for: footprint, userName: userName) ?? [])
    }

    var isEmpty: Bool { footprint.yearly.isEmpty }

    /// The region's per-person distribution for `metric` (what friends are drawn from).
    func distribution(for metric: MetricKey) -> LogNormal? {
        cohort?.regionalDistribution(for: metric)
    }

    func greenerThan(for metric: MetricKey) -> Double? { comparisons[metric]?.greenerThan }

    func leaderboard(for metric: MetricKey) -> [LeaderboardEntry] { leaderboards[metric] ?? [] }

    /// Your place on the overall board (1 = greenest) and your GreenScore.
    var userOverall: (rank: Int, score: PersonalGreenScore)? {
        guard let index = overall.firstIndex(where: \.isUser) else { return nil }
        return (index + 1, overall[index].greenScore)
    }
}
