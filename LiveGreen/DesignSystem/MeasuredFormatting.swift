import Foundation
import GreenCore

extension Measured {
    /// Value with unit in the display unit system, e.g. "18 W", "1.2k lb CO₂e" or "0.12 oz CO₂e".
    var formatted: String {
        "\(formattedNumber)\(DisplayUnits.nbsp)\(displayScale.symbol)"
    }

    /// Range, e.g. "12–24 W". A bound below the unit's resolution reads "0", and a range entirely below it "<0.01 oz",
    /// rather than "0.00072–0.0013 oz".
    var formattedRange: String {
        let scale = displayScale
        let low = self.low * scale.factor, high = self.high * scale.factor
        let unit = "\(DisplayUnits.nbsp)\(scale.symbol)"
        if high != 0, abs(high) < scale.resolution, abs(low) < scale.resolution {
            return "<\(Self.format(scale.resolution))\(unit)"
        }
        func bound(_ number: Double) -> String { abs(number) < scale.resolution ? "0" : Self.format(number) }
        return "\(bound(low))–\(bound(high))\(unit)"
    }

    /// The value alone in `displayScale`, for layouts that set the unit apart ("0.12" beside "oz CO₂e").
    var formattedNumber: String {
        let scale = displayScale
        return Self.format(value * scale.factor, resolution: scale.resolution)
    }

    /// The unit the text forms use: the display unit stepped to suit the value's size (`DisplayUnits.scale`), and
    /// durations under a year in months or days ("1.2 mo", not "0.1 yr"). The value and its range share one unit.
    var displayScale: DisplayScale {
        if unit == .years, abs(high) > 0, abs(high) < 1 {
            return abs(high) < 1.0 / 12 ? DisplayScale(factor: 365, symbol: "days") : DisplayScale(factor: 12, symbol: "mo")
        }
        return DisplayUnits.scale(for: unit, magnitude: value)
    }

    static func format(_ number: Double) -> String {
        let magnitude = abs(number)
        if magnitude >= 10_000 {
            return number.formatted(.number.notation(.compactName).precision(.significantDigits(2)))
        }
        if magnitude >= 100 { return number.formatted(.number.precision(.fractionLength(0))) }
        if magnitude >= 1 { return number.formatted(.number.precision(.significantDigits(1...3))) }
        if magnitude == 0 { return "0" }
        return number.formatted(.number.precision(.significantDigits(1...2)))
    }

    /// `format`, except that a non-zero number below `resolution` reads "<0.01": two significant digits of
    /// 0.0008 oz claim a precision no estimate here has.
    static func format(_ number: Double, resolution: Double) -> String {
        number != 0 && abs(number) < resolution ? "<\(format(resolution))" : format(number)
    }
}

extension Component {
    /// What one unit of a food item's figures covers (`FoodServing.basis`), e.g. "per pack (12 oz)" for a barcoded
    /// pack or "per serving (1 oz)"; nil for other categories.
    var basisLabel: String? {
        guard let basis = FoodServing.basis(of: self) else { return nil }
        let drink = FoodServing.isDrink(self)
        switch basis {
        case .pack(let kg): return "per pack (\(DisplayUnits.foodAmount(kg: kg, isDrink: drink)))"
        case .serving(let kg?): return "per serving (\(DisplayUnits.foodAmount(kg: kg, isDrink: drink)))"
        case .serving(nil): return "per serving"
        }
    }

    /// The basis label as a title, e.g. "Per pack (12 oz)".
    var basisTitle: String? {
        basisLabel.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}
