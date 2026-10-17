import Foundation
import GreenCore

/// Expected grid intensity for each local hour of the day (spec §8.3 forecast).
nonisolated struct HourlyForecast: Hashable, Sendable {
    /// 24 values in gCO2e/kWh, index = local hour.
    var intensities: [Double]
    /// True when built from modeled data (bundled shape or estimated history).
    var isEstimated: Bool

    var average: Double { intensities.reduce(0, +) / Double(max(intensities.count, 1)) }

    func intensity(atHour hour: Int) -> Double {
        intensities[((hour % 24) + 24) % 24]
    }

    /// Median of the same local hour across the given history; nil if any hour has no data.
    static func median(of history: [GridIntensityPoint], calendar: Calendar = .current) -> HourlyForecast? {
        var buckets = Array(repeating: [Double](), count: 24)
        for point in history {
            buckets[calendar.component(.hour, from: point.date)].append(point.gramsCO2ePerKWh)
        }
        guard buckets.allSatisfy({ !$0.isEmpty }) else { return nil }
        let medians = buckets.map { values -> Double in
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        return HourlyForecast(intensities: medians, isEstimated: history.contains(where: \.isEstimated))
    }

    /// The bundled regional 24-h shape scaled to its annual average.
    init(regional record: RegionalGridIntensity) {
        intensities = (0..<24).map { record.annualAverageGPerKWh * (record.hourlyShape.indices.contains($0) ? record.hourlyShape[$0] : 1) }
        isEstimated = true
    }

    init(intensities: [Double], isEstimated: Bool) {
        self.intensities = intensities
        self.isEstimated = isEstimated
    }
}

/// Chooses the cleanest hours for a deferrable load. The integrator may bind GreenCore's
/// `GreenHoursPlanner` here; `LocalGreenHoursPlanner` is the app-side implementation.
nonisolated protocol GreenHoursPlanning: Sendable {
    /// The cleanest `ceil(requiredHours)` hours between `now` and the next `deadlineHour`.
    func plan(forecast: HourlyForecast, requiredHours: Double, deadlineHour: Int,
              now: Date, calendar: Calendar) -> PlugSchedule
}

extension GreenHoursPlanning {
    /// Yearly kg CO2e saved by running `dailyKWh` in the planned hours instead of at the day's average.
    nonisolated func yearlySavingsKg(dailyKWh: Double, schedule: PlugSchedule, forecast: HourlyForecast) -> Double {
        guard let planned = schedule.expectedIntensity else { return 0 }
        return max(0, dailyKWh * 365 * (forecast.average - planned) / 1000)
    }
}

nonisolated struct LocalGreenHoursPlanner: GreenHoursPlanning {
    func plan(forecast: HourlyForecast, requiredHours: Double, deadlineHour: Int,
              now: Date = Date(), calendar: Calendar = .current) -> PlugSchedule {
        let start = calendar.component(.hour, from: now)
        let deadline = ((deadlineHour % 24) + 24) % 24
        // Hours from now until the deadline; a deadline at the current hour means a full day.
        let span = (deadline - start + 24) % 24
        let candidates = (0..<(span == 0 ? 24 : span)).map { (start + $0) % 24 }
        let needed = min(Int(requiredHours.rounded(.up)), candidates.count)
        let chosen = candidates
            .sorted { forecast.intensity(atHour: $0) < forecast.intensity(atHour: $1) }
            .prefix(max(needed, 0))
        let expected = chosen.isEmpty ? nil : chosen.map { forecast.intensity(atHour: $0) }.reduce(0, +) / Double(chosen.count)
        return PlugSchedule(onHours: Array(chosen), timeZoneIdentifier: calendar.timeZone.identifier,
                            createdAt: now, expectedIntensity: expected)
    }
}
