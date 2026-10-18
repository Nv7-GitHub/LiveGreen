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
    /// Where a consumable's frequency came from; nil for identify's own usage and scans saved by older builds.
    public var source: UsageSource?

    public init(hoursOnPerDay: Double? = nil, standbyHoursPerDay: Double? = nil, servingsPerWeek: Double? = nil,
                wearsPerYear: Double? = nil, usesPerWeek: Double? = nil, chargesPerWeek: Double? = nil,
                packsPerWeek: Double? = nil, source: UsageSource? = nil) {
        self.hoursOnPerDay = hoursOnPerDay
        self.standbyHoursPerDay = standbyHoursPerDay
        self.servingsPerWeek = servingsPerWeek
        self.wearsPerYear = wearsPerYear
        self.usesPerWeek = usesPerWeek
        self.chargesPerWeek = chargesPerWeek
        self.packsPerWeek = packsPerWeek
        self.source = source
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

/// Where a consumable's servings, packs or uses a week came from (`UsageDefaults`).
public enum UsageSource: String, Codable, Sendable, Hashable {
    /// LiveGreen's typical week for that kind of item, an assumption until the user says otherwise.
    case typical
    /// The user's answer for the same kind of item on an earlier scan.
    case remembered
    /// The user's answer on this scan.
    case answered

    /// The user said it, here or on an earlier scan.
    public var isUsers: Bool { self != .typical }
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
