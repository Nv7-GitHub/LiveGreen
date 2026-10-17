import Foundation
import GreenCore

/// Recommendation-card estimate (spec §8.3): `kWh/yr × (avgIntensity − scheduledWindowIntensity)`.
nonisolated enum PlugSavingsEstimate {
    /// Default "done by" hour for estimates before a plug is configured.
    static let defaultDeadlineHour = 7

    static func yearly(for candidate: PlugCandidate, outlook: GridOutlook,
                       planner: any GreenHoursPlanning = LocalGreenHoursPlanner(),
                       now: Date = Date(), calendar: Calendar = .current) -> Measured {
        let schedule = planner.plan(forecast: outlook.forecast, requiredHours: candidate.requiredHoursPerDay,
                                    deadlineHour: defaultDeadlineHour, now: now, calendar: calendar)
        let kg = planner.yearlySavingsKg(dailyKWh: candidate.dailyKWh, schedule: schedule, forecast: outlook.forecast)
        let tier: Tier = outlook.forecast.isEstimated ? .estimate : .factorModel
        let source = Source(title: outlook.forecast.isEstimated ? "Regional hourly grid shape" : "Grid intensity history (\(outlook.zone))",
                            tier: tier)
        return Measured(value: kg, relativeRange: 0.3, unit: .kgCO2e, tier: tier, sources: [source])
    }
}
