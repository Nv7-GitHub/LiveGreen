/// Loads whose charging can be shifted to clean-grid hours (spec §7, §8).
public enum DeferrableLoadType: String, Codable, Sendable, Hashable, CaseIterable {
    case eBike
    case eScooter
    case laptopCharger
    case powerBank
    case dishwasher
    case washer
    case evCharger

    public var displayName: String {
        switch self {
        case .eBike: "E-bike charger"
        case .eScooter: "E-scooter charger"
        case .laptopCharger: "Laptop charger"
        case .powerBank: "Power bank"
        case .dishwasher: "Dishwasher"
        case .washer: "Washing machine"
        case .evCharger: "EV charger"
        }
    }
}

/// Marks a component as a candidate for smart-plug green-hours scheduling.
public struct PlugCandidate: Codable, Sendable, Hashable {
    public var loadType: DeferrableLoadType
    /// Charger draw while charging, W.
    public var chargerWatts: Double
    /// Energy needed per day, kWh.
    public var dailyKWh: Double
    /// Estimated yearly savings from scheduling (spec §8.3), once computed.
    public var estimatedSavings: Measured?

    public init(loadType: DeferrableLoadType, chargerWatts: Double, dailyKWh: Double, estimatedSavings: Measured? = nil) {
        self.loadType = loadType
        self.chargerWatts = chargerWatts
        self.dailyKWh = dailyKWh
        self.estimatedSavings = estimatedSavings
    }

    /// Charging hours needed per day (kWh ÷ charger W).
    public var requiredHoursPerDay: Double {
        chargerWatts > 0 ? dailyKWh * 1000 / chargerWatts : 0
    }
}
