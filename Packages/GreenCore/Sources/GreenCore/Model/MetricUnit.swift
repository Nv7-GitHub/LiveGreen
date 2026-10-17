/// Canonical unit for each metric. All `Measured` values are stored in these units.
public enum MetricUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case kgCO2e
    case liters
    case squareMeterYears
    case watts
    case kilowattHoursPerYear
    case years
    case score10
    case grams
    case percent
    case gramsPO4e

    public var symbol: String {
        switch self {
        case .kgCO2e: "kg CO₂e"
        case .liters: "L"
        case .squareMeterYears: "m²·yr"
        case .watts: "W"
        case .kilowattHoursPerYear: "kWh/yr"
        case .years: "yr"
        case .score10: "/10"
        case .grams: "g"
        case .percent: "%"
        case .gramsPO4e: "g PO₄e"
        }
    }
}
