import Foundation

/// A rough yearly carbon estimate for an onboarding profile, itemized so each answer's effect is visible.
/// Food, home energy and clothing are the region's per-capita carbon × each category's share × the same
/// profile modifiers the cohort model uses (meat and dairy meals, home type, floor area and heating, new
/// clothes a year); getting around is computed from the weekly distance per mode; everything else
/// (services, other goods) is the region's remaining share, unmodified.
public struct LifestyleEstimate: Sendable, Hashable {
    public enum Part: String, CaseIterable, Sendable, Hashable {
        case food, homeEnergy, clothing, travel, everythingElse
    }

    /// Yearly kg CO2e per part.
    public let kgPerYear: [Part: Double]
    /// The region's average per-capita footprint, kg CO2e/yr.
    public let regionAverageKg: Double

    public var totalKg: Double { kgPerYear.values.reduce(0, +) }

    /// Average passenger travel's share of a per-capita footprint, replaced by the profile's own commute.
    /// Personal vehicles and air travel are roughly a fifth of a US household footprint (Ivanova et al. 2016;
    /// US EPA Inventory, transportation sector).
    static let averageTravelShare = 0.20

    /// Lifecycle kg CO2e per passenger-km. Car: US EPA, 400 g CO2/mi for a typical passenger vehicle
    /// (≈0.25 kg/km); EV: ~0.2 kWh/km at the US average grid (~0.4 kg/kWh); transit: US bus and rail
    /// average per passenger (FTA/EPA ≈0.1 kg/km); e-bike: ~0.01 kWh/km of charging. Walking and cycling
    /// are zero, so they are not asked about.
    public static let kgPerKm: [CommuteMode: Double] = [
        .car: 0.25, .electricCar: 0.08, .transit: 0.10, .eBike: 0.005,
    ]

    public init(profile: UserProfile, store: ReferenceStore = .bundled) {
        guard let model = CohortModel(profile: profile, store: store) else {
            kgPerYear = [:]
            regionAverageKg = 0
            return
        }
        let total = model.baseline.medians[.carbon] ?? 0
        let reference = model.reference
        func part(_ categories: [Category]) -> Double {
            categories.reduce(0) { $0 + total * reference.share(of: $1, for: .carbon) * model.modifier(for: $1, metric: .carbon) }
        }
        let categoryShare = Category.allCases.reduce(0) { $0 + reference.share(of: $1, for: .carbon) }
        // The heating source shifts home-energy carbon: a heat pump or no heating lowers it, oil and electric
        // resistance raise it. Several sources average evenly.
        let heating = model.heatingCarbonModifier
        let travel = profile.commuteKmPerWeekByMode.reduce(0) { $0 + (Self.kgPerKm[$1.key] ?? 0) * $1.value * 52 }
        let packagingAndCare = total * (reference.share(of: .packaging, for: .carbon) + reference.share(of: .personalCare, for: .carbon))
        kgPerYear = [
            .food: part([.food]),
            .homeEnergy: part([.electronic, .household]) * heating,
            .clothing: part([.clothing]),
            .travel: travel,
            .everythingElse: max(0, total * (1 - categoryShare - Self.averageTravelShare)) + packagingAndCare,
        ]
        regionAverageKg = total
    }
}
