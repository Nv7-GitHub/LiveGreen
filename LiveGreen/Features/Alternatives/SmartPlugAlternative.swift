import Foundation
import GreenCore

/// Builds the locally-added "Shelly smart plug + green-hours scheduling" alternative (spec §7, §8.3).
nonisolated enum SmartPlugAlternative {

    /// Yearly charging carbon of a deferrable load, now and with green-hours scheduling.
    struct ChargingCarbon: Hashable, Sendable {
        var current: Measured
        var scheduled: Measured
        var savings: Measured
    }

    /// The charging comparison per deferrable-load component id, for the chart. The scan pipeline already added
    /// the plug alternative itself; this only needs the grid outlook, loaded once for the whole scan.
    static func charging(for result: ScanResult, profile: UserProfile,
                         services: ServiceContainer) async -> [UUID: ChargingCarbon] {
        guard result.components.contains(where: { $0.plugCandidate != nil }),
              let outlook = try? await GridOutlook.load(grid: services.grid, reference: services.reference,
                                                         profile: profile) else { return [:] }
        var charging: [UUID: ChargingCarbon] = [:]
        for component in result.components {
            guard let candidate = component.plugCandidate else { continue }
            charging[component.id] = chargingCarbon(candidate, forecast: outlook.forecast)
        }
        return charging
    }

    static func make(for component: Component) -> Alternative { .smartPlugScheduling(for: component) }

    static func chargingCarbon(_ candidate: PlugCandidate, forecast: GridForecast) -> ChargingCarbon {
        let savings = GreenHoursPlanner.estimatedSavings(for: candidate, forecast: forecast)
        let kWhPerYear = candidate.dailyKWh * ImpactEngine.daysPerYear
        let current = kWhPerYear * forecast.dayAverage / 1000
        func measured(_ kg: Double) -> Measured {
            Measured(value: max(kg, 0), relativeRange: 0.3, unit: .kgCO2e, tier: savings.tier, sources: savings.sources)
        }
        return ChargingCarbon(current: measured(current), scheduled: measured(current - savings.value), savings: savings)
    }
}
