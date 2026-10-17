/// Component category; determines which metrics apply.
public enum Category: String, Codable, Sendable, Hashable, CaseIterable {
    case food
    case electronic
    case clothing
    case packaging
    case household
    case personalCare

    public var displayName: String {
        switch self {
        case .food: "Food"
        case .electronic: "Electronic"
        case .clothing: "Clothing"
        case .packaging: "Packaging"
        case .household: "Household"
        case .personalCare: "Personal care"
        }
    }

    public var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .electronic: "desktopcomputer"
        case .clothing: "tshirt"
        case .packaging: "shippingbox"
        case .household: "house"
        case .personalCare: "bubbles.and.sparkles"
        }
    }

    /// Static category → metrics applicability table (spec §4), in display order.
    public var applicableMetrics: [MetricKey] {
        switch self {
        case .food:
            [.carbon, .water, .land, .waterPollution, .plasticMass, .recyclablePercent, .decompositionTime]
        case .electronic:
            [.carbon, .powerOn, .standbyPower, .yearlyElectricity, .lifespan, .repairability, .plasticMass, .recyclablePercent]
        case .clothing:
            [.carbon, .water, .land, .waterPollution, .lifespan, .plasticMass, .recyclablePercent, .decompositionTime]
        case .packaging:
            [.carbon, .water, .plasticMass, .recyclablePercent, .decompositionTime]
        case .household:
            [.carbon, .water, .waterPollution, .lifespan, .plasticMass, .recyclablePercent, .decompositionTime]
        case .personalCare:
            [.carbon, .water, .waterPollution, .plasticMass, .recyclablePercent, .decompositionTime]
        }
    }

    public func applies(_ metric: MetricKey) -> Bool { applicableMetrics.contains(metric) }
}
