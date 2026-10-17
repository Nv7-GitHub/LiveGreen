import Foundation

/// A set of charging hours and their expected grid intensity.
public struct GreenWindow: Sendable, Hashable {
    /// Local hours in chronological order from the plan's start.
    public var hours: [Int]
    /// Mean forecast intensity over `hours`, g CO2e/kWh.
    public var averageIntensity: Double

    /// True when the hours form one unbroken block (possibly across midnight).
    public var isContiguous: Bool {
        zip(hours, hours.dropFirst()).allSatisfy { ($0 + 1) % 24 == $1 }
    }

    /// The window as a daily plug schedule.
    public func schedule(timeZone: TimeZone = .current, createdAt: Date = Date()) -> PlugSchedule {
        PlugSchedule(onHours: hours, timeZoneIdentifier: timeZone.identifier, createdAt: createdAt,
                     expectedIntensity: averageIntensity)
    }
}

/// Cleanest-hours plan before a deadline (spec §8.3): a single contiguous block, and the N cleanest hours
/// anywhere in the window (which may be split).
public struct GreenHoursPlan: Sendable, Hashable {
    public var contiguous: GreenWindow
    public var flexible: GreenWindow
    /// Forecast mean over the whole day (unscheduled baseline).
    public var dayAverage: Double
    /// Whole hours of charging the plan covers.
    public var plannedHours: Int
    /// False when the deadline leaves fewer hours than charging needs; the plan then uses every available hour.
    public var fitsDeadline: Bool
}

public enum GreenHoursPlanner {
    /// Plans `requiredHours` of charging (rounded up) from the next whole hour until `deadlineHour`
    /// (local hour the charge must be done by; nil = the next 24 hours).
    public static func plan(forecast: GridForecast, requiredHours: Double, now: Date = Date(),
                            deadlineHour: Int? = nil, calendar: Calendar = .current) -> GreenHoursPlan {
        let start = (calendar.component(.hour, from: now) + 1) % 24
        var span = 24
        if let deadlineHour {
            let distance = ((deadlineHour - start) % 24 + 24) % 24
            span = distance == 0 ? 24 : distance
        }
        let available = (0..<span).map { (start + $0) % 24 }
        let needed = requiredHours > 0 ? Int((requiredHours - 1e-9).rounded(.up)) : 0
        let count = min(needed, available.count)

        let contiguous = cleanestBlock(available, count: count, forecast: forecast)
        let flexibleIndices = available.indices
            .sorted { (forecast.intensity(atHour: available[$0]), $0) < (forecast.intensity(atHour: available[$1]), $1) }
            .prefix(count)
            .sorted()
        let flexible = window(flexibleIndices.map { available[$0] }, forecast: forecast)
        return GreenHoursPlan(contiguous: contiguous, flexible: flexible, dayAverage: forecast.dayAverage,
                              plannedHours: count, fitsDeadline: needed <= available.count)
    }

    /// kg CO2e/yr saved by shifting `kWhPerYear` from the average intensity to the window's: kWh × (avg − window) ÷ 1000.
    public static func yearlySavingsKg(kWhPerYear: Double, averageIntensity: Double, windowIntensity: Double) -> Double {
        max(kWhPerYear * (averageIntensity - windowIntensity) / 1000, 0)
    }

    /// Estimated yearly savings for a deferrable load on recommendation cards (T3, ±40% for forecast error).
    public static func estimatedSavings(for candidate: PlugCandidate, forecast: GridForecast,
                                        now: Date = Date(), calendar: Calendar = .current) -> Measured {
        let plan = plan(forecast: forecast, requiredHours: candidate.requiredHoursPerDay, now: now, calendar: calendar)
        let kg = yearlySavingsKg(kWhPerYear: candidate.dailyKWh * ImpactEngine.daysPerYear,
                                 averageIntensity: plan.dayAverage, windowIntensity: plan.flexible.averageIntensity)
        let sources = forecast.sources + [Source(title: "LiveGreen green-hours planner (spec §8.3)", tier: .factorModel)]
        return Measured(value: kg, relativeRange: 0.4, unit: .kgCO2e, tier: .factorModel, sources: sources)
    }

    /// Savings measured on a real plug: each sample's energy × (day average − intensity at that hour).
    public static func accumulatedSavingsKg(samples: [(kWh: Double, intensity: Double)], dayAverage: Double) -> Double {
        samples.reduce(0) { $0 + $1.kWh * (dayAverage - $1.intensity) / 1000 }
    }

    private static func cleanestBlock(_ available: [Int], count: Int, forecast: GridForecast) -> GreenWindow {
        guard count > 0 else { return window([], forecast: forecast) }
        var best = 0
        var bestSum = Double.infinity
        for offset in 0...(available.count - count) {
            let sum = available[offset..<(offset + count)].reduce(0) { $0 + forecast.intensity(atHour: $1) }
            if sum < bestSum - 1e-9 {
                best = offset
                bestSum = sum
            }
        }
        return window(Array(available[best..<(best + count)]), forecast: forecast)
    }

    private static func window(_ hours: [Int], forecast: GridForecast) -> GreenWindow {
        let mean = hours.isEmpty ? forecast.dayAverage : hours.reduce(0) { $0 + forecast.intensity(atHour: $1) } / Double(hours.count)
        return GreenWindow(hours: hours, averageIntensity: mean)
    }
}
