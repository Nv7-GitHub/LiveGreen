import Foundation

// On-disk formats of the bundled `Resources/ReferenceData/*.json` tables. Each decodes into the public
// record types from `ReferenceProviding` plus the extras in `ReferenceRecords.swift`.

struct RecordsFile<Record: Decodable>: Decodable {
    var records: [Record]
}

struct CitedValue<Value: Decodable>: Decodable {
    var value: Value?
    var values: Value?
    var verified: Bool
    var citation: Source

    var resolved: Value? { value ?? values }
}

struct FoodRecordFile: Decodable {
    var group: String
    var aliases: [String]
    var kgCO2ePerKg: Double
    var litersPerKg: Double
    var landM2YearPerKg: Double
    var gPO4ePerKg: Double
    var stageShares: [LifecycleStage: Double]
    var verified: Bool
    var citation: Source

    var factor: FoodFactor {
        FoodFactor(group: group, kgCO2ePerKg: kgCO2ePerKg, litersPerKg: litersPerKg, landM2YearPerKg: landM2YearPerKg,
                   gPO4ePerKg: gPO4ePerKg, stageShares: stageShares, citation: citation)
    }
}

struct FiberFile: Decodable {
    struct Processing: Decodable {
        var kgCO2ePerKg: Double
        var litersPerKg: Double
        var gPO4ePerKg: Double
        var verified: Bool
        var citation: Source
    }
    struct Lifespan: Decodable {
        var years: Double
        var verified: Bool
        var citation: Source
    }
    struct Record: Decodable {
        var material: String
        var aliases: [String]
        var kgCO2ePerKg: Double
        var litersPerKg: Double
        var landM2YearPerKg: Double
        var gPO4ePerKg: Double
        var isSynthetic: Bool
        var verified: Bool
        var citation: Source

        var factor: FiberFactor {
            FiberFactor(material: material, kgCO2ePerKg: kgCO2ePerKg, litersPerKg: litersPerKg,
                        landM2YearPerKg: landM2YearPerKg, gPO4ePerKg: gPO4ePerKg, isSynthetic: isSynthetic, citation: citation)
        }
    }
    var processing: Processing
    var garmentLifespan: Lifespan
    var records: [Record]
}

struct MaterialRecordFile: Decodable {
    var material: String
    var aliases: [String]
    var decompositionYears: Double
    var recyclablePercent: Double
    var isPlastic: Bool
    var resinCode: Int?
    var kgCO2ePerKg: Double
    var litersPerKg: Double
    var inert: Bool?
    var consumed: Bool?
    var verified: Bool
    var citation: Source

    var factor: MaterialFactor {
        MaterialFactor(
            endOfLife: MaterialEndOfLife(material: material, decompositionYears: decompositionYears,
                                         recyclablePercent: recyclablePercent, isPlastic: isPlastic, citation: citation),
            resinCode: resinCode, kgCO2ePerKg: kgCO2ePerKg, litersPerKg: litersPerKg, isInert: inert ?? false,
            isConsumed: consumed ?? false, verified: verified)
    }
}

struct DeviceRecordFile: Decodable {
    var deviceType: String
    var aliases: [String]
    var onWatts: Double
    var standbyWatts: Double
    var typicalHoursOnPerDay: Double
    var lifespanYears: Double
    var repairability: Double
    var embodiedKgCO2e: Double
    var plasticMassG: Double?
    var recyclablePercent: Double?
    var stageShares: [LifecycleStage: Double]
    var deferrable: DeferrableLoadType?
    var chargerWatts: Double?
    var batteryKWh: Double?
    var referenceScreenInches: Double?
    var verified: Bool
    var citation: Source

    var profile: DeviceProfile {
        DeviceProfile(
            defaults: DeviceDefaults(deviceType: deviceType, onWatts: onWatts, standbyWatts: standbyWatts,
                                     lifespanYears: lifespanYears, repairability: repairability,
                                     embodiedKgCO2e: embodiedKgCO2e, plasticMassG: plasticMassG,
                                     recyclablePercent: recyclablePercent, typicalHoursOnPerDay: typicalHoursOnPerDay,
                                     stageShares: stageShares, citation: citation),
            deferrableLoad: deferrable, chargerWatts: chargerWatts, batteryKWh: batteryKWh,
            referenceScreenInches: referenceScreenInches, verified: verified)
    }
}

struct GridFile: Decodable {
    struct Shape: Decodable {
        var hourly: [Double]
        var verified: Bool
        var citation: Source
    }
    struct Record: Decodable {
        var region: String
        var kind: String
        var annualAverageGPerKWh: Double
        var shapeFamily: String
        var verified: Bool
        var citation: Source
    }
    struct ZIPRange: Decodable {
        var from: Int
        var to: Int
        var subregion: String
    }
    var shapes: [String: Shape]
    var zoneAliases: [String: String]
    var stateSubregions: [String: String]
    var zip3Subregions: [ZIPRange]
    /// `[from, to, state]` triples of 3-digit ZIP prefixes.
    var zip3States: [ZIP3StateRange]
    var records: [Record]
}

struct ZIP3StateRange: Decodable {
    var from: Int
    var to: Int
    var state: String

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        from = try container.decode(Int.self)
        to = try container.decode(Int.self)
        state = try container.decode(String.self)
    }
}

struct PerCapitaFile: Decodable {
    struct Country: Decodable {
        var region: String
        var meanCarbonKg: Double
        var meanWaterL: Double
        var meanLandM2Year: Double
        var meanElectricityKWh: Double
        var verified: Bool
        var citation: Source
        var otherCitations: [Source]
    }
    struct States: Decodable {
        var usAverageTonnes: Double
        var stateRatioMin: Double
        var stateRatioMax: Double
        var verified: Bool
        var citation: Source
        var tonnesPerCapita: [String: Double]
    }
    var countries: [Country]
    var usStates: States
    var sigmas: CitedValue<[String: Double]>
    /// Food: per metric (carbon, land, water).
    var plantBasedFoodShares: CitedValue<[String: Double]>
    /// Food: kg CO2e per meal, keyed meat / dairy.
    var mealCarbon: CitedValue<[String: Double]>
    /// Food: the average diet's meals a week, keyed meat / dairy.
    var averageMealsPerWeek: CitedValue<[String: Double]>
    /// Clothing: averageNewItemsPerYear and baseShare.
    var clothingPurchases: CitedValue<[String: Double]>
    var typicalFloorAreaM2: CitedValue<[String: Double]>
    var spaceConditioningShare: CitedValue<Double>
    var commuteModifiers: CitedValue<[String: Double]>
    var householdSizeExponent: CitedValue<Double>
    var homeTypeModifiers: CitedValue<[String: Double]>
    var heatingModifiers: CitedValue<[String: Double]>
    var heatingCarbonModifiers: CitedValue<[String: Double]>
    var categoryShares: CitedValue<[String: [String: Double]]>
}

struct ASUSRecordFile: Decodable {
    var model: String
    var name: String
    var productType: String
    var totalKgCO2e: Double
    var uncertaintyKgCO2e: Double?
    var annualKWh: Double
    var lifespanYears: Double
    var typicalPowerW: Double
    var stageShares: [LifecycleStage: Double]
    var verified: Bool
    var citation: Source

    var record: ASUSPCFRecord {
        ASUSPCFRecord(model: model, productType: productType, totalKgCO2e: totalKgCO2e, stageShares: stageShares,
                      typicalPowerW: typicalPowerW, lifespanYears: lifespanYears, citation: citation)
    }
}
