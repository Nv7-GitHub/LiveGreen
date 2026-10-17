import Foundation
import GreenCore

/// Builds the locally-added "Shelly smart plug + green-hours scheduling" alternative (spec §7, §8.3).
nonisolated enum SmartPlugAlternative {
    static let name = "Shelly smart plug + green-hours scheduling"

    /// Yearly charging carbon of a deferrable load, now and with green-hours scheduling.
    struct ChargingCarbon: Hashable, Sendable {
        var current: Measured
        var scheduled: Measured
        var savings: Measured
    }

    /// Adds the plug alternative to every deferrable-load component that lacks one, and returns the
    /// charging comparison per component id for the chart.
    static func attach(to result: ScanResult, profile: UserProfile,
                       services: ServiceContainer) async -> (ScanResult, [UUID: ChargingCarbon]) {
        var updated = result
        var charging: [UUID: ChargingCarbon] = [:]
        for index in updated.components.indices {
            let component = updated.components[index]
            guard let candidate = component.plugCandidate,
                  let estimate = await chargingCarbon(candidate, profile: profile, services: services) else { continue }
            charging[component.id] = estimate
            let savings = candidate.estimatedSavings ?? estimate.savings
            updated.components[index].plugCandidate?.estimatedSavings = savings
            if !component.alternatives.contains(where: { $0.kind == .smartPlugScheduling }) {
                updated.components[index].alternatives.append(make(for: updated.components[index]))
            }
        }
        return (updated, charging)
    }

    /// The same device, so every metric matches; its yearly carbon saving comes from the plug candidate
    /// (see `SwapMath.yearlySaving`) because scheduling changes when it charges, not what it is.
    static func make(for component: Component) -> Alternative {
        let load = component.plugCandidate?.loadType.displayName.lowercased() ?? "charger"
        return Alternative(id: stableID(for: component), kind: .smartPlugScheduling, name: name,
                           category: component.category, identifiers: component.identifiers,
                           quantities: component.quantities, usage: component.usage,
                           rationale: "Keep your \(load), but let a plug switch it on only during the cleanest grid hours.",
                           practicality: Practicality(cost: .lower, effort: .easy), metrics: component.metrics)
    }

    /// kWh/yr × the day's average intensity vs. kWh/yr × the planned cleanest hours (spec §8.3), using the
    /// same forecast and planner as the Plugs tab.
    static func chargingCarbon(_ candidate: PlugCandidate, profile: UserProfile,
                               services: ServiceContainer) async -> ChargingCarbon? {
        guard let outlook = try? await GridOutlook.load(grid: services.grid, reference: services.reference,
                                                         profile: profile) else { return nil }
        return chargingCarbon(candidate, forecast: outlook.forecast)
    }

    static func chargingCarbon(_ candidate: PlugCandidate, forecast: GridForecast) -> ChargingCarbon {
        let savings = GreenHoursPlanner.estimatedSavings(for: candidate, forecast: forecast)
        let kWhPerYear = candidate.dailyKWh * ImpactEngine.daysPerYear
        let current = kWhPerYear * forecast.dayAverage / 1000
        func measured(_ kg: Double) -> Measured {
            Measured(value: max(kg, 0), relativeRange: 0.3, unit: .kgCO2e, tier: savings.tier, sources: savings.sources)
        }
        return ChargingCarbon(current: measured(current), scheduled: measured(current - savings.value), savings: savings)
    }

    /// Derived from the component id so a re-run keeps the user's pick.
    private static func stableID(for component: Component) -> UUID {
        var raw = component.id.uuid
        raw.14 ^= 0x5A
        raw.15 ^= 0xA5
        return UUID(uuid: raw)
    }
}
