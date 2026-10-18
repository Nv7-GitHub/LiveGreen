import Foundation

/// A light vehicle's footprint: production from its glider (curb mass minus the traction battery) and battery, and
/// driving from distance × fuel or wall electricity per km for its powertrain, at the user's grid. Production alone
/// is a small part of a car's life (an ICE compact SUV: ≈8 t to make, ≈4.5 t a year to drive), and leaving driving out
/// ranked an EV worse than a petrol car. Carbon follows the durables convention: production + yearly driving ×
/// lifespan, so a year is the lifetime value ÷ lifespan.
struct VehicleModel {
    let factors: VehicleFactors
    let quantities: Quantities

    /// Petrol when identify could not tell: most of the light-vehicle fleet.
    var powertrain: Powertrain { quantities.powertrain ?? .petrol }

    var powertrainFactors: PowertrainFactors? { factors.powertrains[powertrain] ?? factors.powertrains[.petrol] }

    /// Curb mass in tonnes, the typical car's when identify gave none, kept between a motorcycle and a heavy pickup.
    var tonnes: Double { min(max((quantities.massKg ?? factors.defaultMassKg) / 1000, 0.1), 5) }

    var batteryKWh: Double { min(max(powertrainFactors?.tractionBatteryKWh(at: tonnes) ?? 0, 0), 250) }

    /// Everything but the traction battery; never under half the vehicle.
    var gliderKg: Double { max(tonnes * 1000 - batteryKWh * factors.batteryKgPerKWh, tonnes * 500) }

    var gliderKgCO2e: Double { gliderKg * factors.gliderKgCO2ePerKg }
    var batteryKgCO2e: Double { batteryKWh * factors.batteryKgCO2ePerKWh }

    /// Well-to-wheel fuel carbon per km, over the distance not driven on electricity.
    var fuelKgCO2ePerKm: Double {
        guard let pt = powertrainFactors else { return 0 }
        return (1 - pt.electricShare) * pt.fuelKgCO2e(perKmAt: tonnes)
    }

    /// Wall electricity per km, over the distance driven on electricity.
    var wallKWhPerKm: Double {
        guard let pt = powertrainFactors else { return 0 }
        return pt.electricShare * pt.wallKWh(perKmAt: tonnes)
    }

    /// The user's distance when set, else the typical vehicle's.
    func kmPerYear(_ usage: UsageProfile?) -> Double {
        usage?.kmPerWeek.map { max($0, 0) * ImpactEngine.weeksPerYear } ?? factors.kmPerYear
    }

    /// kg CO2e a year of driving: fuel plus charging at `gramsPerKWh`.
    func drivingKgCO2e(kmPerYear km: Double, gramsPerKWh: Double) -> Double {
        km * (fuelKgCO2ePerKm + ImpactEngine.useCarbon(kWh: wallKWhPerKm, gramsPerKWh: gramsPerKWh))
    }

    // MARK: Uncertain inputs

    /// Production carbon, ±30%: the per-kg factor stands for every body style and maker.
    var production: Measured {
        var sources = [factors.gliderCitation]
        if batteryKWh > 0 { sources.append(factors.batteryCitation) }
        return FactorRanges.relative(gliderKgCO2e + batteryKgCO2e, 0.3, unit: .kgCO2e, sources: sources)
    }

    /// Km a year: ±10% when the user set it, ±40% for the national average. The unit is a placeholder; never displayed.
    func distance(_ usage: UsageProfile?) -> Measured {
        let km = kmPerYear(usage)
        guard usage?.kmPerWeek == nil else { return Measured(value: km, relativeRange: 0.1, unit: .grams, tier: .factorModel) }
        return Measured(value: km, relativeRange: 0.4, unit: .grams, tier: .factorModel, sources: [factors.distanceCitation])
    }

    /// Fuel and electricity per km, ±20% between models of one mass. The units are placeholders; never displayed.
    var perKm: (fuel: Measured, electricity: Measured) {
        let sources = powertrainFactors.map { [$0.citation] } ?? []
        return (Measured(value: fuelKgCO2ePerKm, relativeRange: 0.2, unit: .kgCO2e, tier: .factorModel, sources: sources),
                Measured(value: wallKWhPerKm, relativeRange: 0.2, unit: .kilowattHoursPerYear, tier: .factorModel, sources: sources))
    }

    /// Yearly charging electricity for a plug-in; nil when it never plugs in.
    func yearlyElectricity(_ usage: UsageProfile?, seed: UInt64) -> Measured? {
        guard wallKWhPerKm > 0 else { return nil }
        return MonteCarlo(seed: seed).propagate([distance(usage), perKm.electricity], unit: .kilowattHoursPerYear,
                                                salt: "vehicle.kwh") { $0[0] * $0[1] }
    }
}

extension VehicleModel {
    /// Words that name a road vehicle in an item name.
    static let vehicleWords: Set<String> = [
        "car", "suv", "sedan", "saloon", "hatchback", "crossover", "minivan", "van", "pickup", "truck", "coupe",
        "convertible", "wagon", "jeep", "motorcycle", "motorbike", "automobile", "vehicle", "ev",
    ]

    /// Lighter than this it is a toy, a car seat or an e-bike, not a road vehicle.
    static let minimumMassKg = 150.0

    /// Whether identify filed a road vehicle as household or electronic (a parked car as "Hatchback car", an EV as
    /// a plug-in device): a powertrain, a vehicle device type or a vehicle word in the name, on something heavy
    /// enough. Other categories are left alone ("Vans" sneakers stay clothing).
    static func isVehicle(name: String, category: Category, quantities: Quantities) -> Bool {
        guard category == .household || category == .electronic else { return false }
        let mass = quantities.massKg ?? (quantities.powertrain != nil ? minimumMassKg : 0)
        guard mass >= minimumMassKg else { return false }
        let words = Set((name + " " + (quantities.deviceType ?? "")).lowercased()
            .split { !$0.isLetter }.map { $0.hasSuffix("s") && $0.count > 3 ? String($0.dropLast()) : String($0) })
        return quantities.powertrain != nil || !words.isDisjoint(with: vehicleWords)
    }
}

extension ImpactEngine {
    /// The vehicle model for a `vehicle` component; nil for anything else or without the vehicle table.
    func vehicleModel(for component: Component) -> VehicleModel? {
        guard component.category == .vehicle, let factors = store?.vehicles else { return nil }
        return VehicleModel(factors: factors, quantities: component.quantities)
    }

    /// Driving carbon a year at the component's usage and the profile's grid; nil for non-vehicles.
    public func drivingCarbonPerYear(of component: Component, profile: UserProfile) -> Double? {
        vehicleModel(for: component).map {
            $0.drivingKgCO2e(kmPerYear: $0.kmPerYear(component.usage), gramsPerKWh: gridGramsPerKWh(for: profile))
        }
    }

    /// Lifetime carbon = production + yearly driving × lifespan, propagated together, with the stage split it implies
    /// (production split by the table, driving as use).
    func vehicleLifetimeCarbon(production: Measured, of component: Component, model: VehicleModel,
                               profile: UserProfile) -> (carbon: Measured, stages: [LifecycleStage: Double]) {
        let perKm = model.perKm
        let inputs = [production, model.distance(component.usage), perKm.fuel, perKm.electricity,
                      gridMeasured(for: profile), lifespan(of: component)]
        let carbon = MonteCarlo(seed: component.stableSeed).propagate(inputs, unit: .kgCO2e, salt: "vehicle.carbon") { d in
            Self.lifetimeCarbon(embodiedKg: d[0], lifespanYears: d[5],
                                annualUseKg: d[1] * (d[2] + Self.useCarbon(kWh: d[3], gramsPerKWh: d[4])))
        }
        var stages = StageModel.normalized(model.factors.productionStageShares).mapValues { $0 * production.value }
        stages[.use, default: 0] += max(carbon.value - production.value, 0)
        return (carbon, StageModel.normalized(stages))
    }
}
