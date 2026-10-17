import Foundation
import GreenCore

/// Imperial or metric display. GreenCore always computes in metric; conversion happens only when a number
/// is shown.
nonisolated enum UnitSystem: String, CaseIterable, Codable, Sendable {
    case imperial
    case metric

    var displayName: String {
        switch self {
        case .imperial: "Imperial (lb, gal, ft²)"
        case .metric: "Metric (kg, L, m²)"
        }
    }
}

/// Converts canonical metric values for display in the chosen unit system.
enum DisplayUnits {
    static let defaultsKey = "LiveGreen.unitSystem"

    /// Imperial unless the user picked metric in Settings.
    static var system: UnitSystem {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(UnitSystem.init(rawValue:)) ?? .imperial
    }

    static let poundsPerKilogram = 2.204_62
    static let gallonsPerLiter = 0.264_172
    static let squareFeetPerSquareMeter = 10.763_9
    static let ouncesPerGram = 0.035_274

    /// Multiplier from the metric unit to the displayed one.
    static func factor(for unit: MetricUnit, in system: UnitSystem = system) -> Double {
        guard system == .imperial else { return 1 }
        switch unit {
        case .kgCO2e: return poundsPerKilogram
        case .liters: return gallonsPerLiter
        case .squareMeterYears: return squareFeetPerSquareMeter
        case .grams, .gramsPO4e: return ouncesPerGram
        case .watts, .kilowattHoursPerYear, .years, .score10, .percent: return 1
        }
    }

    static func value(_ metricValue: Double, _ unit: MetricUnit, in system: UnitSystem = system) -> Double {
        metricValue * factor(for: unit, in: system)
    }

    static func symbol(_ unit: MetricUnit, in system: UnitSystem = system) -> String {
        guard system == .imperial else { return unit.symbol }
        switch unit {
        case .kgCO2e: return "lb CO₂e"
        case .liters: return "gal"
        case .squareMeterYears: return "ft²·yr"
        case .grams: return "oz"
        case .gramsPO4e: return "oz PO₄e"
        default: return unit.symbol
        }
    }

    /// A carbon amount given in kg, e.g. "12 lb CO₂e".
    static func carbon(kg: Double) -> String {
        "\(Measured.format(value(kg, .kgCO2e))) \(symbol(.kgCO2e))"
    }

    /// Whole-lifestyle carbon given in kg: US short tons in imperial, tonnes in metric.
    static func tons(kg: Double) -> (value: Double, unit: String) {
        system == .imperial ? (kg / 907.185, "tons") : (kg / 1000, "t")
    }

    /// Small carbon amounts (plug savings) given in kg: ounces in imperial, grams in metric.
    static func smallCarbon(kg: Double) -> (value: Double, unit: String) {
        system == .imperial ? (kg * 1000 * ouncesPerGram, "oz CO₂e") : (kg * 1000, "g CO₂e")
    }

    /// Grid carbon intensity given in g/kWh: lb/MWh (the US eGRID convention) in imperial.
    static func gridIntensity(gramsPerKWh: Double) -> String {
        system == .imperial
            ? "\(Measured.format(gramsPerKWh * poundsPerKilogram)) lb CO₂e/MWh"
            : "\(Measured.format(gramsPerKWh)) g CO₂e/kWh"
    }

    /// Short grid-intensity unit for compact labels.
    static var gridIntensityUnit: String { system == .imperial ? "lb/MWh" : "g/kWh" }

    static func gridIntensityValue(gramsPerKWh: Double) -> Double {
        system == .imperial ? gramsPerKWh * poundsPerKilogram : gramsPerKWh
    }

    /// Temperature given in °C.
    static func temperature(celsius: Double) -> (value: Double, unit: String) {
        system == .imperial ? (celsius * 9 / 5 + 32, "°F") : (celsius, "°C")
    }
}

extension Measured {
    /// The value, range and symbol in the display unit system.
    var displayValue: Double { DisplayUnits.value(value, unit) }
    var displayLow: Double { DisplayUnits.value(low, unit) }
    var displayHigh: Double { DisplayUnits.value(high, unit) }
    var displaySymbol: String { DisplayUnits.symbol(unit) }
}
