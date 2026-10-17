import Foundation
import GreenCore

/// The grid picture the plug features plan against: current intensity plus a 24-h forecast.
nonisolated struct GridOutlook: Hashable, Sendable {
    var zone: String
    var current: GridIntensityPoint?
    var forecast: HourlyForecast

    /// Live intensity when available, else the forecast for this hour.
    func intensity(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        if let current, abs(current.date.timeIntervalSince(date)) < 2 * 3600 { return current.gramsCO2ePerKWh }
        return forecast.intensity(atHour: calendar.component(.hour, from: date))
    }

    /// Electricity Maps zone (or reference region) for a profile.
    static func zone(for profile: UserProfile) -> String {
        profile.region.gridZone ?? profile.region.usState.map { "US-\($0)" } ?? profile.region.countryCode
    }

    /// Forecast from 7 days of history (median per hour), falling back to the bundled regional shape.
    static func load(grid: any GridSignal, reference: any ReferenceProviding,
                     profile: UserProfile) async throws -> GridOutlook {
        let zone = zone(for: profile)
        async let latest = try? grid.latest(zone: zone)
        async let history = try? grid.history(zone: zone, hours: 7 * 24)
        let current = await latest
        if let points = await history, let forecast = HourlyForecast.median(of: points) {
            return GridOutlook(zone: zone, current: current, forecast: forecast)
        }
        let regions = [profile.region.gridZone, profile.region.usState, profile.region.countryCode].compactMap { $0 }
        guard let record = regions.lazy.compactMap({ reference.gridIntensity(region: $0) }).first else {
            throw GreenCoreError.notFound
        }
        return GridOutlook(zone: zone, current: current, forecast: HourlyForecast(regional: record))
    }
}
