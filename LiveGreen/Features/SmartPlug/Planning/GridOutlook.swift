import Foundation
import GreenCore

/// The grid picture the plug features plan against: current intensity plus GreenCore's 24-h forecast.
nonisolated struct GridOutlook: Hashable, Sendable {
    var zone: String
    var current: GridIntensityPoint?
    var forecast: GridForecast
    /// Why live history could not be read (missing key, plan or network error), so the UI can say the
    /// forecast falls back to stored readings or the regional shape.
    var historyIssue: String?

    /// Default "done by" hour for estimates before a plug is configured.
    static let defaultDeadlineHour = 7

    /// Live intensity when available, else the forecast for this hour.
    func intensity(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        if let current, abs(current.date.timeIntervalSince(date)) < 2 * 3600 { return current.gramsCO2ePerKWh }
        return forecast.intensity(atHour: calendar.component(.hour, from: date))
    }

    /// Cleanest-hours plan for `requiredHours` of charging before `deadlineHour`, as a daily plug schedule.
    func schedule(requiredHours: Double, deadlineHour: Int, now: Date = Date(),
                  calendar: Calendar = .current) -> PlugSchedule {
        GreenHoursPlanner.plan(forecast: forecast, requiredHours: requiredHours, now: now,
                               deadlineHour: deadlineHour, calendar: calendar)
            .flexible.schedule(timeZone: calendar.timeZone, createdAt: now)
    }

    /// Yearly kg CO2e saved by running `dailyKWh` in the schedule's hours instead of at the day's average.
    func yearlySavingsKg(dailyKWh: Double, schedule: PlugSchedule) -> Double {
        guard let planned = schedule.expectedIntensity else { return 0 }
        return GreenHoursPlanner.yearlySavingsKg(kWhPerYear: dailyKWh * ImpactEngine.daysPerYear,
                                                 averageIntensity: forecast.dayAverage, windowIntensity: planned)
    }

    /// Electricity Maps zone (or reference region) for a profile.
    static func zone(for profile: UserProfile) -> String {
        profile.region.gridZone ?? profile.region.usState.map { "US-\($0)" } ?? profile.region.countryCode
    }

    /// Forecast from up to 7 days of history (median per hour): the live window plus readings archived on
    /// earlier refreshes, falling back to the bundled regional shape.
    static func load(grid: any GridSignal, reference: any ReferenceProviding,
                     profile: UserProfile) async throws -> GridOutlook {
        let zone = zone(for: profile)
        async let latest = try? grid.latest(zone: zone)
        async let history = loadHistory(grid: grid, zone: zone)
        let regions = [profile.region.gridZone, profile.region.usState.map { "US-\($0)" }, profile.region.countryCode]
        let record = regions.compactMap { $0 }.lazy.compactMap { reference.gridIntensity(region: $0) }.first
        let current = await latest
        let (fresh, issue) = await history
        // Only live Electricity Maps readings are archived; bundled and demo signals regenerate theirs.
        let readings = grid is ElectricityMapsClient ? GridHistoryArchive.merge(fresh, zone: zone) : fresh
        guard let forecast = GridForecast.make(history: readings, fallback: record) else {
            throw GreenCoreError.notFound
        }
        return GridOutlook(zone: zone, current: current, forecast: forecast, historyIssue: issue)
    }

    private static func loadHistory(grid: any GridSignal, zone: String) async -> ([GridIntensityPoint], String?) {
        do {
            return (try await grid.history(zone: zone, hours: 7 * 24), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }
}
