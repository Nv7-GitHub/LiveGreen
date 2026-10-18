import GreenCore

/// Slider range, step and unit for a custom answer to a usage question.
extension UsageField {
    static let kmPerMile = 1.609_34

    var customRange: ClosedRange<Double> {
        switch self {
        case .hoursOnPerDay, .standbyHoursPerDay: 0...24
        case .servingsPerWeek, .chargesPerWeek: 0...21
        case .wearsPerYear: 0...365
        case .usesPerWeek: 0...50
        case .packsPerWeek: 0...14
        // Up to about 50,000 km (31,000 mi) a year.
        case .kmPerWeek: 0...1000
        }
    }

    var customStep: Double {
        switch self {
        case .hoursOnPerDay, .standbyHoursPerDay: 0.5
        case .wearsPerYear: 5
        // Fine enough for a pack every few weeks (0.25) and for rates converted from servings (0.18).
        case .packsPerWeek: 0.05
        case .kmPerWeek: 10
        default: 1
        }
    }

    func customLabel(_ value: Double) -> String {
        let number = Self.number(value, field: self)
        let one = value == 1
        switch self {
        case .hoursOnPerDay, .standbyHoursPerDay: return "\(number) h a day"
        case .servingsPerWeek, .packsPerWeek: return "\(number) a week"
        case .chargesPerWeek: return "\(number) \(one ? "charge" : "charges") a week"
        case .wearsPerYear: return "\(number) \(one ? "wear" : "wears") a year"
        case .usesPerWeek: return "\(number) \(one ? "use" : "uses") a week"
        // Stored in km; shown in miles in imperial units.
        case .kmPerWeek:
            let imperial = DisplayUnits.system == .imperial
            let distance = Int((imperial ? value / Self.kmPerMile : value).rounded())
            return "\(distance) \(imperial ? "mi" : "km") a week"
        }
    }

    /// The label beside a verb title ("Used", "Charged", "Worn"): "once a week", "3 times a year". Other fields read
    /// as `customLabel`.
    func rateLabel(_ value: Double) -> String {
        let period: String
        switch self {
        case .usesPerWeek, .chargesPerWeek: period = "a week"
        case .wearsPerYear: period = "a year"
        default: return customLabel(value)
        }
        switch value {
        case 1: return "once \(period)"
        case 2: return "twice \(period)"
        default: return "\(Self.number(value, field: self)) times \(period)"
        }
    }

    private static func number(_ value: Double, field: UsageField) -> String {
        if value.rounded() == value { return String(Int(value)) }
        if field == .packsPerWeek { return value.formatted(.number.precision(.fractionLength(0...2))) }
        return String(format: "%.1f", value)
    }
}
