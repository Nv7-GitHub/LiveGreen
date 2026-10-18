/// Component category; determines which metrics apply.
public enum Category: String, Codable, Sendable, Hashable, CaseIterable {
    case food
    case electronic
    case clothing
    case packaging
    case household
    case personalCare
    /// Cars, SUVs, vans, pickups and motorcycles, whatever the powertrain. Driving dominates their footprint, so they
    /// have their own model (`VehicleModel`) rather than a household material blend. Added last so saved scans decode.
    case vehicle

    public var displayName: String {
        switch self {
        case .food: "Food"
        case .electronic: "Electronic"
        case .clothing: "Clothing"
        case .packaging: "Packaging"
        case .household: "Household"
        case .personalCare: "Personal care"
        case .vehicle: "Vehicle"
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
        case .vehicle: "car"
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
        // Scrapped and shredded, never left to break down; production water is not modeled.
        case .vehicle:
            [.carbon, .yearlyElectricity, .lifespan, .plasticMass, .recyclablePercent]
        }
    }

    public func applies(_ metric: MetricKey) -> Bool { applicableMetrics.contains(metric) }
}
