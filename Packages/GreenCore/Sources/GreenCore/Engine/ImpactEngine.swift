import Foundation

/// Deterministic impact derivations and uncertainty-aware totals (spec §5.6).
///
/// Per-unit semantics of a component's metrics:
/// - food: per serving, a year being `servingsPerWeek × 52` servings; or, for a barcoded pack whose net quantity is
///   on record, per whole pack, a year being `packsPerWeek × 52` packs (`FoodServing.basis`).
/// - packaging, personal care: per unit consumed; a year is `usesPerWeek × 52` units.
/// - household consumables (`Quantities.consumable`: a cleaner, a paper notebook): per item; a year is
///   `usesPerWeek × 52 ÷ usesPerContainer` items (`consumablesPerYear(of:)`).
/// - electronic, clothing, household (durables): per item over its whole life; carbon includes the use phase
///   (embodied + yearly use × lifespan), so a year is the lifetime value ÷ lifespan.
/// - vehicle: likewise per vehicle over its life, the use phase being driving (`VehicleModel`).
/// `yearlyElectricity` is already yearly.
public struct ImpactEngine: Sendable {
    public static let daysPerYear = 365.0
    public static let weeksPerYear = 52.0
    public static let defaultLifespanYears = 5.0
    /// Wall-to-battery charging efficiency for battery loads.
    public static let chargingEfficiency = 0.85
    /// World average grid intensity (Ember 2024, ~473 g/kWh), used only when no region matches.
    public static let fallbackGridGPerKWh = 473.0

    public let reference: any ReferenceProviding

    public init(reference: any ReferenceProviding = ReferenceStore.bundled) {
        self.reference = reference
    }

    var store: ReferenceStore? { reference as? ReferenceStore }

    // MARK: Formulas

    /// kWh/yr = (powerOn × hoursOn + standby × standbyHours) × 365 / 1000.
    public static func yearlyElectricity(powerOnW: Double, hoursOnPerDay: Double,
                                         standbyW: Double, standbyHoursPerDay: Double) -> Double {
        (powerOnW * hoursOnPerDay + standbyW * standbyHoursPerDay) * daysPerYear / 1000
    }

    /// kWh/yr drawn from the wall to charge a battery `chargesPerWeek` times.
    public static func chargingElectricity(batteryKWh: Double, chargesPerWeek: Double,
                                           efficiency: Double = chargingEfficiency) -> Double {
        guard efficiency > 0 else { return 0 }
        return batteryKWh * chargesPerWeek * weeksPerYear / efficiency
    }

    /// kg CO2e from electricity: kWh × g/kWh ÷ 1000.
    public static func useCarbon(kWh: Double, gramsPerKWh: Double) -> Double {
        kWh * gramsPerKWh / 1000
    }

    /// kg CO2e per year: embodied ÷ lifespan + annual use.
    public static func yearlyCarbon(embodiedKg: Double, lifespanYears: Double, annualUseKg: Double) -> Double {
        (lifespanYears > 0 ? embodiedKg / lifespanYears : embodiedKg) + annualUseKg
    }

    /// kg CO2e over the item's life: embodied + annual use × lifespan.
    public static func lifetimeCarbon(embodiedKg: Double, lifespanYears: Double, annualUseKg: Double) -> Double {
        embodiedKg + annualUseKg * lifespanYears
    }

    /// Yearly food impact: per-kg impact × kg per serving × servings per week × 52.
    public static func foodYearly(perKg: Double, servingKg: Double, servingsPerWeek: Double) -> Double {
        perKg * servingKg * servingsPerWeek * weeksPerYear
    }

    // MARK: Grid

    /// Annual grid intensity record for the profile's region.
    public func gridIntensity(for profile: UserProfile) -> RegionalGridIntensity? {
        if let store { return store.gridIntensity(for: profile.region) }
        let region = profile.region
        let candidates = [region.gridZone, region.usState.map { "US-\($0)" }, region.countryCode].compactMap { $0 }
        return candidates.lazy.compactMap(reference.gridIntensity(region:)).first
    }

    /// g CO2e/kWh for the profile, falling back to the world average.
    public func gridGramsPerKWh(for profile: UserProfile) -> Double {
        gridIntensity(for: profile)?.annualAverageGPerKWh ?? Self.fallbackGridGPerKWh
    }

    /// Grid intensity in g/kWh as a `Measured` input for propagation (±15%: annual averages differ from the
    /// hours a device actually runs). The unit is a placeholder; this value is never displayed.
    func gridMeasured(for profile: UserProfile) -> Measured {
        let record = gridIntensity(for: profile)
        let value = record?.annualAverageGPerKWh ?? Self.fallbackGridGPerKWh
        let sources = record.map { [$0.citation] } ?? [Source(title: "Ember world average grid intensity (2024)", tier: .factorModel)]
        return Measured(value: value, relativeRange: 0.15, unit: .grams, tier: .factorModel, sources: sources)
    }

    // MARK: Derived electricity

    /// Yearly electricity from power metrics and usage: battery charging when the device has a battery and
    /// `chargesPerWeek` is known, else on/standby power × hours. Nil when power or hours are unknown.
    public func derivedYearlyElectricity(for component: Component) -> Measured? {
        // A vehicle's electricity is its charging for the distance driven, nil when it never plugs in.
        if let vehicle = vehicleModel(for: component) {
            return vehicle.yearlyElectricity(component.usage, seed: component.stableSeed)
        }
        let profile = store?.deviceProfile(for: component)
        let usage = component.usage
        let mc = MonteCarlo(seed: component.stableSeed)
        if let battery = profile?.batteryKWh, let charges = usage?.chargesPerWeek {
            let kWh = Self.chargingElectricity(batteryKWh: battery, chargesPerWeek: charges)
            let source = profile.map { [$0.defaults.citation] } ?? []
            return Measured(value: kWh, relativeRange: 0.25, unit: .kilowattHoursPerYear, tier: .factorModel, sources: source)
        }
        guard let powerOn = component.metrics[.powerOn],
              let hoursOn = usage?.hoursOnPerDay ?? profile?.defaults.typicalHoursOnPerDay else { return nil }
        let standby = component.metrics[.standbyPower] ?? Measured.exact(0, unit: .watts, tier: powerOn.tier)
        let standbyHours = usage?.standbyHoursPerDay ?? max(0, 24 - hoursOn)
        return mc.propagate([powerOn, standby], unit: .kilowattHoursPerYear, salt: "kwh") {
            Self.yearlyElectricity(powerOnW: $0[0], hoursOnPerDay: hoursOn, standbyW: $0[1], standbyHoursPerDay: standbyHours)
        }
    }
}

extension Component {
    /// What the device table is searched by: the item's device type, else the name of an electronic. Nothing else
    /// is matched by name, so a paper "spiral notebook" never gets a laptop's lifespan and citation.
    public var deviceLookupKey: String? {
        if let type = quantities.deviceType?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty { return type }
        return category == .electronic ? name : nil
    }
}

extension ReferenceStore {
    /// The component's device profile under `Component.deviceLookupKey`.
    public func deviceProfile(for component: Component) -> DeviceProfile? {
        component.deviceLookupKey.flatMap(deviceProfile(deviceType:))
    }
}
