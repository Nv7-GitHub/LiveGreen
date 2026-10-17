import Foundation
import GreenCore

/// Hourly grid readings kept across refreshes. A free Electricity Maps key only returns the last 24 h, so
/// the 7-day per-hour median (spec §8.3) is built from the readings stored on earlier refreshes.
nonisolated enum GridHistoryArchive {
    static let retention: TimeInterval = 7 * 24 * 3600

    /// Newest archived reading for the zone, if any.
    static func newestDate(zone: String, defaults: UserDefaults = .standard) -> Date? {
        stored(zone: zone, defaults: defaults).last?.date
    }

    private static func stored(zone: String, defaults: UserDefaults) -> [GridIntensityPoint] {
        defaults.data(forKey: "gridHistory.\(zone)")
            .flatMap { try? JSONDecoder().decode([GridIntensityPoint].self, from: $0) }?
            .sorted { $0.date < $1.date } ?? []
    }

    /// Merges fresh readings into the zone's archive, drops readings older than the retention window,
    /// saves the result and returns it oldest first.
    static func merge(_ fresh: [GridIntensityPoint], zone: String, now: Date = Date(),
                      defaults: UserDefaults = .standard) -> [GridIntensityPoint] {
        let key = "gridHistory.\(zone)"
        let stored = stored(zone: zone, defaults: defaults)
        var byHour: [Int: GridIntensityPoint] = [:]
        for point in stored + fresh where now.timeIntervalSince(point.date) <= retention {
            byHour[Int(point.date.timeIntervalSince1970 / 3600)] = point
        }
        let merged = byHour.values.sorted { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: key) }
        return merged
    }
}
