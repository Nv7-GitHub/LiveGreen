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

/// The unit one amount is shown in: the multiplier from its metric value, the symbol, and the smallest amount
/// worth printing in it.
nonisolated struct DisplayScale: Equatable, Sendable {
    let factor: Double
    let symbol: String
    /// Non-zero amounts below this print as "<0.01" rather than with digits the data cannot back up.
    var resolution = 0.01
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

    /// The display unit's symbol. Land is land occupation, area held for a year (m²·yr, ft²·yr). Spaces inside a
    /// symbol are non-breaking, so "lb CO₂e" never wraps apart.
    static func symbol(_ unit: MetricUnit, in system: UnitSystem = system) -> String {
        let symbol = switch (unit, system) {
        case (_, .metric): unit.symbol
        case (.kgCO2e, .imperial): "lb CO₂e"
        case (.liters, .imperial): "gal"
        case (.squareMeterYears, .imperial): "ft²·yr"
        case (.grams, .imperial): "oz"
        default: unit.symbol
        }
        return symbol.replacingOccurrences(of: " ", with: nbsp)
    }

    /// Joins a number to its unit so a line never breaks between them.
    static let nbsp = "\u{00A0}"

    /// The unit for an amount of this size: the display unit, except that tiny carbon and water step down
    /// ("0.12 oz CO₂e", "3 fl oz" instead of "0.0073 lb", "0.024 gal") and car-scale plastic steps up ("353 lb", not
    /// "5,644 oz"). `metricValue` is in the canonical unit; only its size matters.
    static func scale(for unit: MetricUnit, magnitude metricValue: Double, in system: UnitSystem = system) -> DisplayScale {
        let base = DisplayScale(factor: factor(for: unit, in: system), symbol: symbol(unit, in: system))
        let shown = abs(metricValue) * base.factor
        let tiny = shown > 0 && shown < 0.1
        switch (unit, system) {
        case (.kgCO2e, .imperial) where tiny: return DisplayScale(factor: 1000 * ouncesPerGram, symbol: "oz\(nbsp)CO₂e")
        case (.kgCO2e, .metric) where tiny: return DisplayScale(factor: 1000, symbol: "g\(nbsp)CO₂e")
        case (.liters, .imperial) where tiny: return DisplayScale(factor: fluidOuncesPerLiter, symbol: "fl\(nbsp)oz")
        case (.liters, .metric) where tiny: return DisplayScale(factor: 1000, symbol: "mL")
        case (.grams, .imperial) where shown >= 16: return DisplayScale(factor: poundsPerKilogram / 1000, symbol: "lb")
        case (.grams, .metric) where shown >= 1000: return DisplayScale(factor: 0.001, symbol: "kg")
        default: return base
        }
    }

    /// An amount with its unit in the unit that suits its size, e.g. "12 lb CO₂e" or "0.5 oz CO₂e".
    static func amount(_ metricValue: Double, _ unit: MetricUnit) -> String {
        let scale = scale(for: unit, magnitude: metricValue)
        return "\(Measured.format(metricValue * scale.factor, resolution: scale.resolution))\(nbsp)\(scale.symbol)"
    }

    /// A carbon amount given in kg, e.g. "12 lb CO₂e".
    static func carbon(kg: Double) -> String {
        amount(kg, .kgCO2e)
    }

    /// Whole-lifestyle carbon given in kg: US short tons in imperial, tonnes in metric.
    static func tons(kg: Double) -> (value: Double, unit: String) {
        system == .imperial ? (kg / 907.185, "tons") : (kg / 1000, "t")
    }

    /// Small carbon amounts (plug savings) given in kg: ounces in imperial, grams in metric.
    static func smallCarbon(kg: Double) -> (value: Double, unit: String) {
        system == .imperial ? (kg * 1000 * ouncesPerGram, "oz\(nbsp)CO₂e") : (kg * 1000, "g\(nbsp)CO₂e")
    }

    /// Grid carbon intensity given in g/kWh: lb/MWh (the US eGRID convention) in imperial.
    static func gridIntensity(gramsPerKWh: Double) -> String {
        system == .imperial
            ? "\(Measured.format(gramsPerKWh * poundsPerKilogram))\(nbsp)lb\(nbsp)CO₂e/MWh"
            : "\(Measured.format(gramsPerKWh))\(nbsp)g\(nbsp)CO₂e/kWh"
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
        func printed(_ number: Double) -> String { number.formatted(.number.precision(.fractionLength(0...1))) }
        switch (system, isDrink) {
        case (.imperial, true):
            return "\(printed(kg * fluidOuncesPerLiter))\(nbsp)fl\(nbsp)oz"
        case (.imperial, false):
            let ounces = kg * 1000 * ouncesPerGram
            return ounces >= 16 ? "\(printed(kg * poundsPerKilogram))\(nbsp)lb" : "\(printed(ounces))\(nbsp)oz"
        case (.metric, true):
            return kg >= 1 ? "\(printed(kg))\(nbsp)L" : "\(printed(kg * 1000))\(nbsp)mL"
        case (.metric, false):
            return kg >= 1 ? "\(printed(kg))\(nbsp)kg" : "\(printed(kg * 1000))\(nbsp)g"
        }
    }

    /// Temperature given in °C.
    static func temperature(celsius: Double) -> (value: Double, unit: String) {
        system == .imperial ? (celsius * 9 / 5 + 32, "°F") : (celsius, "°C")
    }
}

extension Measured {
    /// The value, range and symbol in the display unit system's base unit (lb, gal, oz…), the same for every value of
    /// a metric, so charts can put two values on one axis. Text uses `displayScale`, which suits the value's size.
    var displayValue: Double { DisplayUnits.value(value, unit) }
    var displayLow: Double { DisplayUnits.value(low, unit) }
    var displayHigh: Double { DisplayUnits.value(high, unit) }
    var displaySymbol: String { DisplayUnits.symbol(unit) }
}
