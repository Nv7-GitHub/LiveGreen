import Foundation

/// Extra material data beyond `MaterialEndOfLife`: production footprint and resin code, for the factor model.
public struct MaterialFactor: Codable, Sendable, Hashable {
    public var endOfLife: MaterialEndOfLife
    /// SPI resin identification code 1–7, for plastics.
    public var resinCode: Int?
    /// Cradle-to-gate production footprint.
    public var kgCO2ePerKg: Double
    public var litersPerKg: Double
    public var verified: Bool

    public var citation: Source { endOfLife.citation }
}

/// Extra device data beyond `DeviceDefaults`: deferrable-load info and screen scaling.
public struct DeviceProfile: Codable, Sendable, Hashable {
    public var defaults: DeviceDefaults
    /// Set when the device's charging can be shifted to clean hours.
    public var deferrableLoad: DeferrableLoadType?
    /// Typical charger/load draw while charging, W.
    public var chargerWatts: Double?
    /// Energy per full charge (EV: typical daily session), kWh.
    public var batteryKWh: Double?
    /// Screen size the typical figures refer to; on-power scales with screen area.
    public var referenceScreenInches: Double?
    public var verified: Bool
}

/// Garment-making overhead added to fiber impacts per kg of garment.
public struct GarmentProcessing: Codable, Sendable, Hashable {
    public var kgCO2ePerKg: Double
    public var litersPerKg: Double
    public var gPO4ePerKg: Double
    public var lifespanYears: Double
    public var citation: Source
    public var lifespanCitation: Source
}

/// Cohort-model inputs that sit alongside per-capita baselines (spec §9).
public struct CohortReference: Sendable, Hashable {
    /// Share of the per-capita total attributable to each scanned category, per metric.
    public var categoryShares: [MetricKey: [Category: Double]]
    public var clothingModifiers: [ClothingHabit: Double]
    public var commuteModifiers: [CommuteMode: Double]
    /// Household electricity (and appliance carbon) by housing type, relative to the average home.
    public var homeTypeModifiers: [HomeType: Double]
    /// Household electricity by main heating source, relative to the average home.
    public var heatingModifiers: [HeatingSource: Double]
    public var citations: [Source]

    public init(categoryShares: [MetricKey: [Category: Double]], clothingModifiers: [ClothingHabit: Double],
                commuteModifiers: [CommuteMode: Double], homeTypeModifiers: [HomeType: Double] = [:],
                heatingModifiers: [HeatingSource: Double] = [:], citations: [Source]) {
        self.categoryShares = categoryShares
        self.clothingModifiers = clothingModifiers
        self.commuteModifiers = commuteModifiers
        self.homeTypeModifiers = homeTypeModifiers
        self.heatingModifiers = heatingModifiers
        self.citations = citations
    }

    public func share(of category: Category, for metric: MetricKey) -> Double {
        categoryShares[metric]?[category] ?? 0
    }
}

/// An ASUS PCF record with the report's stated uncertainty and yearly energy.
public struct ASUSPCFDetail: Codable, Sendable, Hashable {
    public var record: ASUSPCFRecord
    /// Marketing name, e.g. "ASUS Zenbook 14 OLED (UX3405M)".
    public var name: String
    /// The report's ± figure, when stated.
    public var uncertaintyKgCO2e: Double?
    /// Yearly energy consumption from the report (ENERGY STAR TEC-style), kWh.
    public var annualKWh: Double
}

/// Per-record provenance used by integrity checks and the "verified" flag in the UI.
public struct ReferenceRecordInfo: Sendable, Hashable {
    public var table: String
    public var key: String
    public var verified: Bool
    public var citation: Source
}
