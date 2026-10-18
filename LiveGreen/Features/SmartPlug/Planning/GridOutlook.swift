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
        let plan = GreenHoursPlanner.plan(forecast: forecast, requiredHours: requiredHours, now: now,
                                          deadlineHour: deadlineHour, calendar: calendar)
        return plan.flexible.schedule(timeZone: calendar.timeZone, createdAt: now, baselineIntensity: plan.dayAverage)
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
        let live = isLive(grid)
        // Unstructured so a slow live request keeps running (and archives) after we stop waiting for it.
        let latestTask = Task { try? await grid.latest(zone: zone) }
        let historyTask = Task { () -> Result<[GridIntensityPoint], any Error> in
            do {
                let points = try await grid.history(zone: zone, hours: 7 * 24)
                if live { _ = GridHistoryArchive.merge(points, zone: zone) }
                return .success(points)
            } catch {
                return .failure(error)
            }
        }
        let patience = live ? patience(zone: zone) : nil
        let regions = [profile.region.gridZone, profile.region.usState.map { "US-\($0)" }, profile.region.countryCode]
        let record = regions.compactMap { $0 }.lazy.compactMap { reference.gridIntensity(region: $0) }.first

        var fresh: [GridIntensityPoint] = []
        var issue: String?
        switch await value(of: historyTask, within: patience) {
        case .success(let points)?: fresh = points
        case .failure(let error)?: issue = error.localizedDescription
        case nil: issue = "Live grid data is still loading; planning from saved readings for now."
        }
        let current = await value(of: latestTask, within: patience) ?? nil
        // Only live readings are archived; bundled and demo signals regenerate theirs.
        let readings = live ? GridHistoryArchive.merge(fresh, zone: zone) : fresh
        guard let forecast = GridForecast.make(history: readings, fallback: record) else {
            throw GreenCoreError.notFound
        }
        return GridOutlook(zone: zone, current: current, forecast: forecast, historyIssue: issue)
    }

    /// Seconds to wait for live grid data before planning from archived readings. EIA's grid monitor takes
    /// ~30 s for a fresh query (repeats within a minute are instant), so with no recent archive we wait for
    /// it; with one, we plan right away and the request still finishes and archives in the background.
    static func patience(zone: String, now: Date = Date()) -> Double {
        guard let newest = GridHistoryArchive.newestDate(zone: zone), now.timeIntervalSince(newest) < 12 * 3600 else {
            return 75
        }
        return 3
    }

    /// Starts the live history request early (app launch) so the Plugs screens find it cached or archived.
    static func warm(grid: any GridSignal, profile: UserProfile) {
        guard isLive(grid) else { return }
        let zone = zone(for: profile)
        Task.detached(priority: .utility) {
            if let points = try? await grid.history(zone: zone, hours: 7 * 24) {
                _ = GridHistoryArchive.merge(points, zone: zone)
            }
        }
    }

    static func isLive(_ grid: any GridSignal) -> Bool {
        grid is ElectricityMapsClient || grid is EIAGridClient
    }

    /// The task's value, or nil if it is not ready within `seconds` (nil waits indefinitely). The task is
    /// not cancelled.
    private static func value<T: Sendable>(of task: Task<T, Never>, within seconds: Double?) async -> T? {
        guard let seconds else { return await task.value }
        return await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
