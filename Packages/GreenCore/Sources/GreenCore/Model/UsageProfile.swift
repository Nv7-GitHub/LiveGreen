/// How a component is used; drives yearly figures in the impact engine.
public struct UsageProfile: Codable, Sendable, Hashable {
    public var hoursOnPerDay: Double?
    public var standbyHoursPerDay: Double?
    public var servingsPerWeek: Double?
    public var wearsPerYear: Double?
    public var usesPerWeek: Double?
    /// Charges per week for deferrable loads (e-bike, scooter…).
    public var chargesPerWeek: Double?
    /// Packs per week for food scored per pack (`FoodServing.basis`).
    public var packsPerWeek: Double?

    public init(hoursOnPerDay: Double? = nil, standbyHoursPerDay: Double? = nil, servingsPerWeek: Double? = nil,
                wearsPerYear: Double? = nil, usesPerWeek: Double? = nil, chargesPerWeek: Double? = nil,
                packsPerWeek: Double? = nil) {
        self.hoursOnPerDay = hoursOnPerDay
        self.standbyHoursPerDay = standbyHoursPerDay
        self.servingsPerWeek = servingsPerWeek
        self.wearsPerYear = wearsPerYear
        self.usesPerWeek = usesPerWeek
        self.chargesPerWeek = chargesPerWeek
        self.packsPerWeek = packsPerWeek
    }

    public subscript(field: UsageField) -> Double? {
        get {
            switch field {
            case .hoursOnPerDay: hoursOnPerDay
            case .standbyHoursPerDay: standbyHoursPerDay
            case .servingsPerWeek: servingsPerWeek
            case .wearsPerYear: wearsPerYear
            case .usesPerWeek: usesPerWeek
            case .chargesPerWeek: chargesPerWeek
            case .packsPerWeek: packsPerWeek
            }
        }
        set {
            switch field {
            case .hoursOnPerDay: hoursOnPerDay = newValue
            case .standbyHoursPerDay: standbyHoursPerDay = newValue
            case .servingsPerWeek: servingsPerWeek = newValue
            case .wearsPerYear: wearsPerYear = newValue
            case .usesPerWeek: usesPerWeek = newValue
            case .chargesPerWeek: chargesPerWeek = newValue
            case .packsPerWeek: packsPerWeek = newValue
            }
        }
    }

    /// Returns a copy with one field set (used when the user answers a question).
    public func setting(_ field: UsageField, to value: Double) -> UsageProfile {
        var copy = self
        copy[field] = value
        return copy
    }
}

/// Addressable fields of `UsageProfile`, so question answers can target them.
public enum UsageField: String, Codable, Sendable, Hashable, CaseIterable {
    case hoursOnPerDay
    case standbyHoursPerDay
    case servingsPerWeek
    case wearsPerYear
    case usesPerWeek
    case chargesPerWeek
    case packsPerWeek

    /// Fields identify may ask about. Packs per week only exists for food the app scores per pack, which identify
    /// cannot know about, so its questions stay in servings (`ImpactEngine.applyingAnswer` converts them).
    public static var askable: [UsageField] { allCases.filter { $0 != .packsPerWeek } }
}
