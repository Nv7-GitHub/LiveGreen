import Foundation

/// Bundled reference tables (spec §5.4, `Resources/ReferenceData/*.json`). Every record has a citation.
/// Lookups are synchronous; keys are lowercased snake_case identifiers.
public protocol ReferenceProviding: Sendable {
    func foodFactor(group: String) -> FoodFactor?
    func fiberFactor(material: String) -> FiberFactor?
    func endOfLife(material: String) -> MaterialEndOfLife?
    func deviceDefaults(deviceType: String) -> DeviceDefaults?
    /// eGRID subregion, Electricity Maps zone, or ISO country code.
    func gridIntensity(region: String) -> RegionalGridIntensity?
    /// US state code or ISO country code.
    func perCapita(region: String) -> PerCapitaBaseline?
    func asusPCF(model: String) -> ASUSPCFRecord?
}

/// Per-kg food impacts (Poore & Nemecek 2018 / Our World in Data).
public struct FoodFactor: Codable, Sendable, Hashable {
    public var group: String
    public var kgCO2ePerKg: Double
    public var litersPerKg: Double
    public var landM2YearPerKg: Double
    public var gPO4ePerKg: Double
    public var stageShares: [LifecycleStage: Double]
    public var citation: Source

    public init(group: String, kgCO2ePerKg: Double, litersPerKg: Double, landM2YearPerKg: Double,
                gPO4ePerKg: Double, stageShares: [LifecycleStage: Double] = [:], citation: Source) {
        self.group = group
        self.kgCO2ePerKg = kgCO2ePerKg
        self.litersPerKg = litersPerKg
        self.landM2YearPerKg = landM2YearPerKg
        self.gPO4ePerKg = gPO4ePerKg
        self.stageShares = stageShares
        self.citation = citation
    }
}

/// Per-kg textile fiber impacts.
public struct FiberFactor: Codable, Sendable, Hashable {
    public var material: String
    public var kgCO2ePerKg: Double
    public var litersPerKg: Double
    public var landM2YearPerKg: Double
    public var gPO4ePerKg: Double
    public var isSynthetic: Bool
    public var citation: Source

    public init(material: String, kgCO2ePerKg: Double, litersPerKg: Double, landM2YearPerKg: Double,
                gPO4ePerKg: Double, isSynthetic: Bool, citation: Source) {
        self.material = material
        self.kgCO2ePerKg = kgCO2ePerKg
        self.litersPerKg = litersPerKg
        self.landM2YearPerKg = landM2YearPerKg
        self.gPO4ePerKg = gPO4ePerKg
        self.isSynthetic = isSynthetic
        self.citation = citation
    }
}

/// End-of-life properties of a material.
public struct MaterialEndOfLife: Codable, Sendable, Hashable {
    public var material: String
    public var decompositionYears: Double
    public var recyclablePercent: Double
    public var isPlastic: Bool
    public var citation: Source

    public init(material: String, decompositionYears: Double, recyclablePercent: Double, isPlastic: Bool, citation: Source) {
        self.material = material
        self.decompositionYears = decompositionYears
        self.recyclablePercent = recyclablePercent
        self.isPlastic = isPlastic
        self.citation = citation
    }
}

/// Typical figures by device type (ENERGY STAR / EU repairability averages).
public struct DeviceDefaults: Codable, Sendable, Hashable {
    public var deviceType: String
    public var onWatts: Double
    public var standbyWatts: Double
    public var lifespanYears: Double
    public var repairability: Double
    public var embodiedKgCO2e: Double
    public var plasticMassG: Double?
    public var recyclablePercent: Double?
    public var typicalHoursOnPerDay: Double
    public var stageShares: [LifecycleStage: Double]
    public var citation: Source

    public init(deviceType: String, onWatts: Double, standbyWatts: Double, lifespanYears: Double, repairability: Double,
                embodiedKgCO2e: Double, plasticMassG: Double? = nil, recyclablePercent: Double? = nil,
                typicalHoursOnPerDay: Double, stageShares: [LifecycleStage: Double] = [:], citation: Source) {
        self.deviceType = deviceType
        self.onWatts = onWatts
        self.standbyWatts = standbyWatts
        self.lifespanYears = lifespanYears
        self.repairability = repairability
        self.embodiedKgCO2e = embodiedKgCO2e
        self.plasticMassG = plasticMassG
        self.recyclablePercent = recyclablePercent
        self.typicalHoursOnPerDay = typicalHoursOnPerDay
        self.stageShares = stageShares
        self.citation = citation
    }
}

/// Annual average grid intensity plus a 24-hour shape for fallback forecasting.
public struct RegionalGridIntensity: Codable, Sendable, Hashable {
    public var region: String
    public var annualAverageGPerKWh: Double
    /// 24 multipliers (mean 1.0), index = local hour.
    public var hourlyShape: [Double]
    public var citation: Source

    public init(region: String, annualAverageGPerKWh: Double, hourlyShape: [Double], citation: Source) {
        self.region = region
        self.annualAverageGPerKWh = annualAverageGPerKWh
        self.hourlyShape = hourlyShape
        self.citation = citation
    }

    /// Modeled intensity at a local hour.
    public func intensity(atHour hour: Int) -> Double {
        guard hourlyShape.count == 24 else { return annualAverageGPerKWh }
        return annualAverageGPerKWh * hourlyShape[((hour % 24) + 24) % 24]
    }
}

/// Per-capita yearly baseline and spread for the cohort model (spec §9).
public struct PerCapitaBaseline: Codable, Sendable, Hashable {
    public var region: String
    /// Median yearly per-capita value per metric (carbon, water, land, yearlyElectricity), canonical units.
    public var medians: [MetricKey: Double]
    /// Lognormal σ per metric from published inequality figures.
    public var sigmas: [MetricKey: Double]
    /// Multiplier on the median by diet.
    public var dietModifiers: [Diet: Double]
    /// Median scales with householdSize^(exponent - 1) for shared-household economies of scale.
    public var householdSizeExponent: Double
    public var citation: Source

    public init(region: String, medians: [MetricKey: Double], sigmas: [MetricKey: Double],
                dietModifiers: [Diet: Double] = [:], householdSizeExponent: Double = 1, citation: Source) {
        self.region = region
        self.medians = medians
        self.sigmas = sigmas
        self.dietModifiers = dietModifiers
        self.householdSizeExponent = householdSizeExponent
        self.citation = citation
    }
}

/// Curated public ASUS Product Carbon Footprint figure.
public struct ASUSPCFRecord: Codable, Sendable, Hashable {
    public var model: String
    public var productType: String
    public var totalKgCO2e: Double
    public var stageShares: [LifecycleStage: Double]
    public var typicalPowerW: Double?
    public var lifespanYears: Double?
    public var citation: Source

    public init(model: String, productType: String, totalKgCO2e: Double, stageShares: [LifecycleStage: Double],
                typicalPowerW: Double? = nil, lifespanYears: Double? = nil, citation: Source) {
        self.model = model
        self.productType = productType
        self.totalKgCO2e = totalKgCO2e
        self.stageShares = stageShares
        self.typicalPowerW = typicalPowerW
        self.lifespanYears = lifespanYears
        self.citation = citation
    }
}
