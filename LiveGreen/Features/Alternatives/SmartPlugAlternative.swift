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

    /// kWh/yr × average intensity vs. kWh/yr × intensity of the cleanest hours that cover the charge (spec §8.3).
    static func chargingCarbon(_ candidate: PlugCandidate, profile: UserProfile,
                               services: ServiceContainer) async -> ChargingCarbon? {
        guard let (hourly, source) = await hourlyIntensity(profile: profile, services: services),
              hourly.count == 24 else { return nil }
        let hours = min(max(Int(candidate.requiredHoursPerDay.rounded(.up)), 1), 24)
        let average = hourly.reduce(0, +) / 24
        let cleanest = hourly.sorted().prefix(hours)
        let window = cleanest.reduce(0, +) / Double(cleanest.count)
        let kWhPerYear = candidate.dailyKWh * 365
        func measured(_ kg: Double) -> Measured {
            Measured(value: max(kg, 0), relativeRange: 0.3, unit: .kgCO2e, tier: .factorModel, sources: [source])
        }
        return ChargingCarbon(current: measured(kWhPerYear * average / 1000),
                              scheduled: measured(kWhPerYear * window / 1000),
                              savings: measured(kWhPerYear * (average - window) / 1000))
    }

    /// A 24-value local-hour intensity profile: bundled regional shape first, then the grid history.
    private static func hourlyIntensity(profile: UserProfile,
                                        services: ServiceContainer) async -> ([Double], Source)? {
        let region = profile.region
        let keys = [region.gridZone, region.usState.map { "US-\($0)" }, region.countryCode].compactMap { $0 }
        for key in keys {
            if let record = services.reference.gridIntensity(region: key) {
                return ((0..<24).map(record.intensity(atHour:)), record.citation)
            }
        }
        guard let zone = region.gridZone,
              let history = try? await services.grid.history(zone: zone, hours: 24 * 7), !history.isEmpty else { return nil }
        var buckets = Array(repeating: [Double](), count: 24)
        let calendar = Calendar.current
        for point in history { buckets[calendar.component(.hour, from: point.date)].append(point.gramsCO2ePerKWh) }
        let overall = history.map(\.gramsCO2ePerKWh).reduce(0, +) / Double(history.count)
        let medians = buckets.map { $0.isEmpty ? overall : $0.sorted()[$0.count / 2] }
        return (medians, Source(title: "Grid intensity history, zone \(zone)", tier: .factorModel))
    }

    /// Derived from the component id so a re-run keeps the user's pick.
    private static func stableID(for component: Component) -> UUID {
        var raw = component.id.uuid
        raw.14 ^= 0x5A
        raw.15 ^= 0xA5
        return UUID(uuid: raw)
    }
}
