import Foundation
import GreenCore

/// Everything the Compare tab shows, derived from saved scans, the profile and the reference tables.
struct CompareAnalysis {
    let footprint: ScannedFootprint
    let cohort: LocalCohortModel
    let trend: [MetricKey: [TrendPoint]]

    struct TrendPoint: Identifiable, Hashable {
        let index: Int
        let date: Date
        /// Share (0–1) of peers with a larger footprint at that point.
        let greenerThan: Double
        var id: Int { index }
    }

    init(scans: [ScanResult], profile: UserProfile, reference: any ReferenceProviding) {
        let footprint = ScannedFootprint(scans: scans)
        self.footprint = footprint
        cohort = LocalCohortModel(profile: profile, reference: reference, scope: footprint.categories)

        var trend: [MetricKey: [TrendPoint]] = [:]
        for (index, entry) in ScannedFootprint.history(of: scans).enumerated() {
            let pointCohort = LocalCohortModel(profile: profile, reference: reference, scope: entry.footprint.categories)
            for metric in CohortMetric.all {
                guard let value = entry.footprint.totals[metric], pointCohort.distribution(for: metric) != nil else { continue }
                trend[metric, default: []].append(TrendPoint(
                    index: index, date: entry.date, greenerThan: pointCohort.greenerThan(for: metric, value: value)))
            }
        }
        self.trend = trend
    }

    /// The user's scoped yearly value for a metric, when it is comparable.
    func userValue(for metric: MetricKey) -> Double? {
        guard cohort.distribution(for: metric) != nil else { return nil }
        return footprint.totals[metric]
    }

    func greenerThan(for metric: MetricKey) -> Double? {
        userValue(for: metric).map { cohort.greenerThan(for: metric, value: $0) }
    }
}
