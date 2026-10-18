import Foundation

/// Extra material data beyond `MaterialEndOfLife`: production footprint and resin code, for the factor model.
public struct MaterialFactor: Codable, Sendable, Hashable {
    public var endOfLife: MaterialEndOfLife
    /// SPI resin identification code 1–7, for plastics.
    public var resinCode: Int?
    /// Cradle-to-gate production footprint.
    public var kgCO2ePerKg: Double
    public var litersPerKg: Double
    /// Does not break down (glass, ceramic, stainless steel). It lingers without polluting, so it gets no
    /// decomposition time.
    public var isInert: Bool
    /// Used up rather than thrown away (food, a cleaner's formula): never packaging, never in end-of-life metrics.
    public var isConsumed: Bool
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
    public var commuteModifiers: [CommuteMode: Double]
    /// Household electricity (and appliance carbon) by housing type, relative to the average home.
    public var homeTypeModifiers: [HomeType: Double]
    /// Household electricity by heating source, relative to the average home.
    public var heatingModifiers: [HeatingSource: Double]
    /// Home-energy carbon by heating source, relative to the average home: burning fuel or running resistance
    /// heaters adds carbon that a heat pump or an unheated home does not.
    public var heatingCarbonModifiers: [HeatingSource: Double]
    /// Food's footprint from meat and dairy meals a week.
    public var meals: MealFactors
    /// Clothing's footprint from new clothes bought a year.
    public var clothing: ClothingFactors
    /// Home energy from floor area against a typical home of the same type.
    public var homeSize: HomeSizeFactors
    public var citations: [Source]

    public init(categoryShares: [MetricKey: [Category: Double]], commuteModifiers: [CommuteMode: Double],
                homeTypeModifiers: [HomeType: Double] = [:], heatingModifiers: [HeatingSource: Double] = [:],
                heatingCarbonModifiers: [HeatingSource: Double] = [:], meals: MealFactors = MealFactors(),
                clothing: ClothingFactors = ClothingFactors(), homeSize: HomeSizeFactors = HomeSizeFactors(),
                citations: [Source]) {
        self.categoryShares = categoryShares
        self.commuteModifiers = commuteModifiers
        self.homeTypeModifiers = homeTypeModifiers
        self.heatingModifiers = heatingModifiers
        self.heatingCarbonModifiers = heatingCarbonModifiers
        self.meals = meals
        self.clothing = clothing
        self.homeSize = homeSize
        self.citations = citations
    }

    public func share(of category: Category, for metric: MetricKey) -> Double {
        categoryShares[metric]?[category] ?? 0
    }

    /// The heating sources' modifiers averaged evenly (each source taken to heat an equal part of the home);
    /// no sources means an unheated home (`.none`). Carbon uses `heatingCarbonModifiers`, every other metric
    /// the electricity table.
    public func heatingModifier(for sources: Set<HeatingSource>, metric: MetricKey = .yearlyElectricity) -> Double {
        let table = metric == .carbon ? heatingCarbonModifiers : heatingModifiers
        let used = sources.subtracting([.none])
        guard !used.isEmpty else { return table[.none] ?? 1 }
        return used.reduce(0) { $0 + (table[$1] ?? 1) } / Double(used.count)
    }
}

/// Food's footprint from how many meals a week have meat or dairy as an important component, relative to the
/// average diet. A plant-based diet keeps `plantBasedShare` of it; the rest (the animal-product part) scales
/// with the meal counts, a meat meal weighing `kgCO2ePerMeatMeal` against a dairy meal's `kgCO2ePerDairyMeal`.
/// The average counts give 1.
public struct MealFactors: Sendable, Hashable {
    /// Share of the average diet's footprint left on a plant-based diet, per metric (carbon, land, water).
    public var plantBasedShare: [MetricKey: Double]
    /// kg CO2e a meal centred on meat (or on dairy) adds over a plant-based meal.
    public var kgCO2ePerMeatMeal: Double
    public var kgCO2ePerDairyMeal: Double
    /// The average diet's meals a week with meat and with dairy.
    public var averageMeatMealsPerWeek: Double
    public var averageDairyMealsPerWeek: Double

    public init(plantBasedShare: [MetricKey: Double] = [:], kgCO2ePerMeatMeal: Double = 0, kgCO2ePerDairyMeal: Double = 0,
                averageMeatMealsPerWeek: Double = 0, averageDairyMealsPerWeek: Double = 0) {
        self.plantBasedShare = plantBasedShare
        self.kgCO2ePerMeatMeal = kgCO2ePerMeatMeal
        self.kgCO2ePerDairyMeal = kgCO2ePerDairyMeal
        self.averageMeatMealsPerWeek = averageMeatMealsPerWeek
        self.averageDairyMealsPerWeek = averageDairyMealsPerWeek
    }

    /// Multiplier on food's share of the per-capita total for `metric`; 1 without data for the metric.
    public func modifier(meatMeals: Int, dairyMeals: Int, metric: MetricKey) -> Double {
        let average = averageMeatMealsPerWeek * kgCO2ePerMeatMeal + averageDairyMealsPerWeek * kgCO2ePerDairyMeal
        guard let plant = plantBasedShare[metric], average > 0 else { return 1 }
        let yours = Double(meatMeals) * kgCO2ePerMeatMeal + Double(dairyMeals) * kgCO2ePerDairyMeal
        return plant + (1 - plant) * yours / average
    }
}

/// Clothing's footprint from new clothes bought a year, relative to the average buyer: `baseShare` (shoes,
/// second-hand finds, upkeep) stays and the rest scales with new items.
public struct ClothingFactors: Sendable, Hashable {
    public var averageNewItemsPerYear: Double
    public var baseShare: Double

    public init(averageNewItemsPerYear: Double = 0, baseShare: Double = 0) {
        self.averageNewItemsPerYear = averageNewItemsPerYear
        self.baseShare = baseShare
    }

    /// Multiplier on clothing's share of the per-capita total; 1 without data.
    public func modifier(newItemsPerYear: Double) -> Double {
        guard averageNewItemsPerYear > 0 else { return 1 }
        return baseShare + (1 - baseShare) * max(0, newItemsPerYear) / averageNewItemsPerYear
    }
}

/// Home energy from floor area: space heating and cooling (`spaceConditioningShare` of household energy)
/// scale with area against the typical home of the same type; water heating, appliances and lighting do not.
public struct HomeSizeFactors: Sendable, Hashable {
    /// Average floor area by home type, m².
    public var typicalFloorAreaM2: [HomeType: Double]
    public var spaceConditioningShare: Double

    /// Area ratios beyond this are clamped, so a stray answer cannot scale home energy without bound.
    static let ratioRange = 0.2...5.0

    public init(typicalFloorAreaM2: [HomeType: Double] = [:], spaceConditioningShare: Double = 0) {
        self.typicalFloorAreaM2 = typicalFloorAreaM2
        self.spaceConditioningShare = spaceConditioningShare
    }

    /// Multiplier on home energy for a home of `areaM2`; 1 for nil (typical size) or without data.
    public func modifier(areaM2: Double?, homeType: HomeType) -> Double {
        guard let areaM2, let typical = typicalFloorAreaM2[homeType], typical > 0 else { return 1 }
        let ratio = min(max(areaM2 / typical, Self.ratioRange.lowerBound), Self.ratioRange.upperBound)
        return 1 + spaceConditioningShare * (ratio - 1)
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
