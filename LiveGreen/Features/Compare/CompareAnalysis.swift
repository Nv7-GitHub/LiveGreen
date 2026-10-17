import Foundation
import GreenCore

/// Everything the Compare tab shows, derived from saved scans, the profile and the bundled reference tables
/// through GreenCore's `CohortModel` (spec §9).
nonisolated struct CompareAnalysis: Sendable {
    let footprint: ScannedFootprint
    /// Nil when there is no per-capita baseline for the profile's region.
    let cohort: CohortModel?
    let comparisons: [MetricKey: CohortComparison]
    let trend: [MetricKey: [TrendPoint]]

    struct TrendPoint: Identifiable, Hashable, Sendable {
        let index: Int
        let date: Date
        /// Share (0–1) of peers with a larger footprint at that point.
        let greenerThan: Double
        var id: Int { index }
    }

    static let empty = CompareAnalysis(footprint: .empty, cohort: nil, comparisons: [:], trend: [:])

    init(footprint: ScannedFootprint, cohort: CohortModel?, comparisons: [MetricKey: CohortComparison],
         trend: [MetricKey: [TrendPoint]]) {
        self.footprint = footprint
        self.cohort = cohort
        self.comparisons = comparisons
        self.trend = trend
    }

    init(scans: [ScanResult], profile: UserProfile, store: ReferenceStore = .bundled) {
        let engine = ImpactEngine(reference: store)
        let footprint = ScannedFootprint.from(scans: scans, engine: engine)
        let cohort = CohortModel(profile: profile, store: store)
        var comparisons: [MetricKey: CohortComparison] = [:]
        var trend: [MetricKey: [TrendPoint]] = [:]
        if let cohort {
            for comparison in cohort.compare(footprint) { comparisons[comparison.metric] = comparison }
            for metric in CohortMetric.all {
                let points = Percentiles.trend(scans: scans, model: cohort, metric: metric, engine: engine)
                trend[metric] = points.enumerated().map { TrendPoint(index: $0, date: $1.date, greenerThan: $1.greenerThan) }
            }
        }
        self.init(footprint: footprint, cohort: cohort, comparisons: comparisons, trend: trend)
    }

    var isEmpty: Bool { footprint.yearly.isEmpty }

    /// Peer distribution scoped to the categories that contribute to `metric`.
    func distribution(for metric: MetricKey) -> LogNormal? {
        cohort?.distribution(for: metric, categories: footprint.categories(for: metric))
    }

    func greenerThan(for metric: MetricKey) -> Double? { comparisons[metric]?.greenerThan }

    func leaderboard(for metric: MetricKey) -> [LeaderboardEntry] {
        cohort?.leaderboard(for: footprint, metric: metric) ?? []
    }

    /// Avatar symbol per leaderboard entry id.
    func avatarSymbols(for metric: MetricKey) -> [String: String] {
        guard let cohort else { return [:] }
        let friends = cohort.simulatedFriends(categories: footprint.categories(for: metric))
        return Dictionary(uniqueKeysWithValues: friends.map { ("friend-\($0.id)", $0.avatarSymbol) })
    }
}
