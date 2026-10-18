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
    static let fluidOuncesPerLiter = 33.814

    /// Multiplier from the metric unit to the displayed one.
    static func factor(for unit: MetricUnit, in system: UnitSystem = system) -> Double {
        guard system == .imperial else { return 1 }
        switch unit {
        case .kgCO2e: return poundsPerKilogram
        case .liters: return gallonsPerLiter
        case .squareMeterYears: return squareFeetPerSquareMeter
        case .grams: return ouncesPerGram
        // Nutrient pollution is a few grams at most; in ounces it would read 0.07 oz.
        case .gramsPO4e, .watts, .kilowattHoursPerYear, .years, .score10, .percent: return 1
        }
    }

    static func value(_ metricValue: Double, _ unit: MetricUnit, in system: UnitSystem = system) -> Double {
        metricValue * factor(for: unit, in: system)
    }

    /// Land is stored as land occupation (m²·yr, area held for a year), which reads as "per year" to most
    /// people, so it is shown as plain area: the land it took to make the item.
    static func symbol(_ unit: MetricUnit, in system: UnitSystem = system) -> String {
        switch (unit, system) {
        case (.squareMeterYears, .metric): return "m²"
        case (_, .metric): return unit.symbol
        case (.kgCO2e, .imperial): return "lb CO₂e"
        case (.liters, .imperial): return "gal"
        case (.squareMeterYears, .imperial): return "ft²"
        case (.grams, .imperial): return "oz"
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

    /// A food amount given in kg, or a drink's in liters, as a label would print it: oz (lb from a pound up) or
    /// fl oz in imperial, g or kg, mL or L in metric.
    static func foodAmount(kg: Double, isDrink: Bool, in system: UnitSystem = system) -> String {
        // At most one decimal, like "11.2 fl oz" or "340 g" on a label.
        func amount(_ number: Double) -> String { number.formatted(.number.precision(.fractionLength(0...1))) }
        switch (system, isDrink) {
        case (.imperial, true):
            return "\(amount(kg * fluidOuncesPerLiter)) fl oz"
        case (.imperial, false):
            let ounces = kg * 1000 * ouncesPerGram
            return ounces >= 16 ? "\(amount(kg * poundsPerKilogram)) lb" : "\(amount(ounces)) oz"
        case (.metric, true):
            return kg >= 1 ? "\(amount(kg)) L" : "\(amount(kg * 1000)) mL"
        case (.metric, false):
            return kg >= 1 ? "\(amount(kg)) kg" : "\(amount(kg * 1000)) g"
        }
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
