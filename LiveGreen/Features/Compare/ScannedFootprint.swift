import Foundation
import GreenCore

/// The user's annualized footprint across saved scans, per cohort metric (spec §9).
/// An item scanned more than once counts once, using its most recent scan.
struct ScannedFootprint: Hashable {
    var totals: [MetricKey: Double] = [:]
    /// Categories that contributed to each metric's total; they scope the peer baseline.
    var categories: [MetricKey: Set<GreenCore.Category>] = [:]
    var itemCount = 0

    /// - Parameter scans: any order; later-dated scans win for repeated items.
    init(scans: [ScanResult]) {
        var seen = Set<String>()
        for scan in scans.sorted(by: { $0.date > $1.date }) {
            for component in scan.components where seen.insert(Self.dedupeKey(component)).inserted {
                itemCount += 1
                for metric in CohortMetric.all {
                    guard let measured = component.metrics[metric] else { continue }
                    totals[metric, default: 0] += measured.value
                    categories[metric, default: []].insert(component.category)
                }
            }
        }
    }

    /// Footprints after each scan, oldest first, for the percentile trend.
    static func history(of scans: [ScanResult]) -> [(date: Date, footprint: ScannedFootprint)] {
        let ordered = scans.sorted { $0.date < $1.date }
        return ordered.indices.map { index in
            (ordered[index].date, ScannedFootprint(scans: Array(ordered[...index])))
        }
    }

    private static func dedupeKey(_ component: Component) -> String {
        component.identifiers.cacheKey ?? "name:\(component.category.rawValue)|\(component.name.lowercased())"
    }
}
