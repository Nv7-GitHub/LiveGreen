import Foundation
import GreenCore

extension Measured {
    /// Value with unit, e.g. "18 W" or "1.2k kg CO₂e".
    var formatted: String { "\(Self.format(value)) \(unit.symbol)" }

    /// Range, e.g. "12–24 W".
    var formattedRange: String { "\(Self.format(low))–\(Self.format(high)) \(unit.symbol)" }

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
