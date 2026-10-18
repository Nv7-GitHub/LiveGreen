import GreenCore

/// Slider range, step and unit for a custom answer to a usage question.
extension UsageField {
    var customRange: ClosedRange<Double> {
        switch self {
        case .hoursOnPerDay, .standbyHoursPerDay: 0...24
        case .servingsPerWeek, .chargesPerWeek: 0...21
        case .wearsPerYear: 0...365
        case .usesPerWeek: 0...50
        case .packsPerWeek: 0...14
        }
    }

    var customStep: Double {
        switch self {
        case .hoursOnPerDay, .standbyHoursPerDay: 0.5
        case .wearsPerYear: 5
        case .packsPerWeek: 0.5
        default: 1
        }
    }

    func customLabel(_ value: Double) -> String {
        let number = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        switch self {
        case .hoursOnPerDay, .standbyHoursPerDay: return "\(number) h a day"
        case .servingsPerWeek, .packsPerWeek: return "\(number) a week"
        case .chargesPerWeek: return "\(number) charges a week"
        case .wearsPerYear: return "\(number) wears a year"
        case .usesPerWeek: return "\(number) uses a week"
        }
    }
}
