import Foundation

/// Expected grid intensity for each local hour of the next day (spec §8.3).
public struct GridForecast: Sendable, Hashable {
    /// 24 values in g CO2e/kWh, index = local hour.
    public var hourly: [Double]
    /// True when no history was available and the bundled regional shape was used.
    public var isFallback: Bool
    public var sources: [Source]

    public init(hourly: [Double], isFallback: Bool, sources: [Source] = []) {
        precondition(hourly.count == 24, "GridForecast needs 24 hourly values")
        self.hourly = hourly
        self.isFallback = isFallback
        self.sources = sources
    }

    /// Mean over the day: what unscheduled charging would see on average.
    public var dayAverage: Double { hourly.reduce(0, +) / 24 }

    public func intensity(atHour hour: Int) -> Double { hourly[((hour % 24) + 24) % 24] }

    /// The bundled regional 24-hour shape scaled to its annual average.
    public static func fallback(_ record: RegionalGridIntensity) -> GridForecast {
        GridForecast(hourly: (0..<24).map(record.intensity(atHour:)), isFallback: true, sources: [record.citation])
    }

    /// Median of the same local hour over the last 7 days of history. Hours with no readings come from the
    /// bundled shape, rescaled to the level of the history that does exist. Nil with neither input.
    public static func make(history: [GridIntensityPoint], fallback: RegionalGridIntensity?,
                            now: Date = Date(), calendar: Calendar = .current) -> GridForecast? {
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        var byHour = [[Double]](repeating: [], count: 24)
        for point in history where point.date > weekAgo && point.date <= now && point.gramsCO2ePerKWh.isFinite {
            byHour[calendar.component(.hour, from: point.date)].append(point.gramsCO2ePerKWh)
        }
        let medians = byHour.map(median)
        let known = medians.indices.filter { medians[$0] != nil }
        guard !known.isEmpty else { return fallback.map(Self.fallback) }

        var hourly = medians.map { $0 ?? 0 }
        let missing = medians.indices.filter { medians[$0] == nil }
        if !missing.isEmpty {
            if let fallback {
                let historyMean = known.reduce(0) { $0 + hourly[$1] } / Double(known.count)
                let shapeMean = known.reduce(0) { $0 + fallback.intensity(atHour: $1) } / Double(known.count)
                let scale = shapeMean > 0 ? historyMean / shapeMean : 1
                for hour in missing { hourly[hour] = fallback.intensity(atHour: hour) * scale }
            } else {
                for hour in missing { hourly[hour] = nearestKnown(to: hour, known: known, values: hourly) }
            }
        }
        var sources = [Source(title: "Grid intensity history (median of last 7 days by hour)", tier: .exactRecord)]
        if !missing.isEmpty, let fallback { sources.append(fallback.citation) }
        return GridForecast(hourly: hourly, isFallback: false, sources: sources)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func nearestKnown(to hour: Int, known: [Int], values: [Double]) -> Double {
        let closest = known.min { circularDistance($0, hour) < circularDistance($1, hour) } ?? hour
        return values[closest]
    }

    private static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % 24
        return min(d, 24 - d)
    }
}
