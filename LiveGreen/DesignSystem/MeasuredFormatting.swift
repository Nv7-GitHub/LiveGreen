import Foundation
import GreenCore

extension Measured {
    /// Value with unit in the display unit system, e.g. "18 W" or "1.2k lb CO₂e".
    var formatted: String {
        let scale = textScale
        return "\(Self.format(value * scale.factor)) \(scale.symbol)"
    }

    /// Range, e.g. "12–24 W".
    var formattedRange: String {
        let scale = textScale
        return "\(Self.format(low * scale.factor))–\(Self.format(high * scale.factor)) \(scale.symbol)"
    }

    /// Multiplier and symbol for the text forms: the display unit, except that durations under a year read
    /// in months or days ("1.2 mo", not "0.1 yr").
    private var textScale: (factor: Double, symbol: String) {
        if unit == .years, abs(high) > 0, abs(high) < 1 {
            return abs(high) < 1.0 / 12 ? (365, "days") : (12, "mo")
        }
        return (DisplayUnits.factor(for: unit), displaySymbol)
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
}
