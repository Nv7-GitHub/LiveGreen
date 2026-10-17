/// The 12 environmental metrics LiveGreen reports (spec §4).
public enum MetricKey: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
    /// kg CO2e (embodied + use-phase).
    case carbon
    /// L freshwater (blue water).
    case water
    /// m²·year of land use.
    case land
    /// W while on.
    case powerOn
    /// W in standby.
    case standbyPower
    /// kWh per year.
    case yearlyElectricity
    /// Years of expected service.
    case lifespan
    /// 0–10, EU repairability index style.
    case repairability
    /// g of plastic, item + packaging.
    case plasticMass
    /// % of mass that is recyclable.
    case recyclablePercent
    /// Years to decompose.
    case decompositionTime
    /// g PO4e (eutrophication).
    case waterPollution

    public var unit: MetricUnit {
        switch self {
        case .carbon: .kgCO2e
        case .water: .liters
        case .land: .squareMeterYears
        case .powerOn, .standbyPower: .watts
        case .yearlyElectricity: .kilowattHoursPerYear
        case .lifespan, .decompositionTime: .years
        case .repairability: .score10
        case .plasticMass: .grams
        case .recyclablePercent: .percent
        case .waterPollution: .gramsPO4e
        }
    }

    public var displayName: String {
        switch self {
        case .carbon: "Carbon"
        case .water: "Water"
        case .land: "Land use"
        case .powerOn: "Power (on)"
        case .standbyPower: "Standby power"
        case .yearlyElectricity: "Yearly electricity"
        case .lifespan: "Lifespan"
        case .repairability: "Repairability"
        case .plasticMass: "Plastic"
        case .recyclablePercent: "Recyclable"
        case .decompositionTime: "Decomposition"
        case .waterPollution: "Water pollution"
        }
    }

    /// SF Symbol name for UI use.
    public var systemImage: String {
        switch self {
        case .carbon: "carbon.dioxide.cloud"
        case .water: "drop"
        case .land: "leaf"
        case .powerOn: "bolt"
        case .standbyPower: "powersleep"
        case .yearlyElectricity: "bolt.badge.clock"
        case .lifespan: "hourglass"
        case .repairability: "wrench.and.screwdriver"
        case .plasticMass: "takeoutbag.and.cup.and.straw"
        case .recyclablePercent: "arrow.3.trianglepath"
        case .decompositionTime: "clock.arrow.circlepath"
        case .waterPollution: "water.waves"
        }
    }

    /// True when a larger value is better (lifespan, repairability, recyclability).
    public var higherIsBetter: Bool {
        switch self {
        case .lifespan, .repairability, .recyclablePercent: true
        default: false
        }
    }
}
