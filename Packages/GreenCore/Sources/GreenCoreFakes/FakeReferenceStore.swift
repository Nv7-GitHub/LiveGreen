import Foundation
import GreenCore

/// Small in-memory reference tables with a handful of representative records.
public struct FakeReferenceStore: ReferenceProviding {
    public var foods: [String: FoodFactor]
    public var fibers: [String: FiberFactor]
    public var materials: [String: MaterialEndOfLife]
    public var devices: [String: DeviceDefaults]
    public var grids: [String: RegionalGridIntensity]
    public var perCapitas: [String: PerCapitaBaseline]
    public var asus: [String: ASUSPCFRecord]

    public init() {
        let owid = Source(title: "Poore & Nemecek (2018), via Our World in Data",
                          url: URL(string: "https://ourworldindata.org/environmental-impacts-of-food"), tier: .factorModel)
        let fiber = Source(title: "Textile Exchange Material Change Insights", tier: .factorModel)
        let eol = Source(title: "NOAA Marine Debris Program", tier: .factorModel)
        let device = Source(title: "ENERGY STAR category averages", tier: .factorModel)
        let egrid = Source(title: "EPA eGRID2022", url: URL(string: "https://www.epa.gov/egrid"), tier: .factorModel)
        let perCapita = Source(title: "Our World in Data per-capita indicators", tier: .factorModel)
        let asusSource = Source(title: "ASUS Product Carbon Footprint", url: URL(string: "https://esg.asus.com"), tier: .exactRecord)

        foods = [
            "beef": FoodFactor(group: "beef", kgCO2ePerKg: 99.5, litersPerKg: 1451, landM2YearPerKg: 326, gPO4ePerKg: 301, citation: owid),
            "potatoes": FoodFactor(group: "potatoes", kgCO2ePerKg: 0.46, litersPerKg: 59, landM2YearPerKg: 0.88, gPO4ePerKg: 3.5, citation: owid),
            "tofu": FoodFactor(group: "tofu", kgCO2ePerKg: 3.2, litersPerKg: 149, landM2YearPerKg: 2.2, gPO4ePerKg: 6.2, citation: owid),
        ]
        fibers = [
            "cotton": FiberFactor(material: "cotton", kgCO2ePerKg: 2.1, litersPerKg: 2100, landM2YearPerKg: 5.4, gPO4ePerKg: 20, isSynthetic: false, citation: fiber),
            "polyester": FiberFactor(material: "polyester", kgCO2ePerKg: 3.1, litersPerKg: 60, landM2YearPerKg: 0.1, gPO4ePerKg: 1.2, isSynthetic: true, citation: fiber),
        ]
        materials = [
            "aluminium": MaterialEndOfLife(material: "aluminium", decompositionYears: 200, recyclablePercent: 95, isPlastic: false, citation: eol),
            "polyethylene": MaterialEndOfLife(material: "polyethylene", decompositionYears: 450, recyclablePercent: 10, isPlastic: true, citation: eol),
            "paperboard": MaterialEndOfLife(material: "paperboard", decompositionYears: 0.2, recyclablePercent: 70, isPlastic: false, citation: eol),
        ]
        devices = [
            "laptop": DeviceDefaults(deviceType: "laptop", onWatts: 30, standbyWatts: 1, lifespanYears: 4, repairability: 5,
                                     embodiedKgCO2e: 250, plasticMassG: 350, recyclablePercent: 60, typicalHoursOnPerDay: 6,
                                     stageShares: [.materials: 0.45, .manufacturing: 0.25, .transport: 0.05, .use: 0.22, .endOfLife: 0.03],
                                     citation: device),
            "monitor": DeviceDefaults(deviceType: "monitor", onWatts: 25, standbyWatts: 0.3, lifespanYears: 6, repairability: 4,
                                      embodiedKgCO2e: 380, plasticMassG: 1800, recyclablePercent: 55, typicalHoursOnPerDay: 6,
                                      citation: device),
        ]
        let shape: [Double] = [0.88, 0.86, 0.85, 0.85, 0.87, 0.92, 1.0, 1.06, 1.04, 0.98, 0.92, 0.88,
                               0.86, 0.87, 0.92, 1.0, 1.1, 1.2, 1.24, 1.2, 1.12, 1.04, 0.96, 0.92]
        grids = [
            "US-NE-ISNE": RegionalGridIntensity(region: "US-NE-ISNE", annualAverageGPerKWh: 245, hourlyShape: shape, citation: egrid),
            "US": RegionalGridIntensity(region: "US", annualAverageGPerKWh: 371, hourlyShape: shape, citation: egrid),
        ]
        perCapitas = [
            "US": PerCapitaBaseline(
                region: "US",
                medians: [.carbon: 14_900, .water: 1_200_000, .land: 9_000, .yearlyElectricity: 4_400],
                sigmas: [.carbon: 0.55, .water: 0.5, .land: 0.6, .yearlyElectricity: 0.5],
                dietModifiers: [.omnivore: 1.0, .flexitarian: 0.85, .vegetarian: 0.7, .vegan: 0.6],
                householdSizeExponent: 0.8, citation: perCapita),
        ]
        asus = [
            "ux3405ma": ASUSPCFRecord(model: "UX3405MA", productType: "Notebook", totalKgCO2e: 233,
                                      stageShares: [.materials: 0.62, .manufacturing: 0.08, .transport: 0.04, .use: 0.24, .endOfLife: 0.02],
                                      typicalPowerW: 28, lifespanYears: 4, citation: asusSource),
        ]
    }

    private static func key(_ s: String) -> String { s.lowercased().replacingOccurrences(of: " ", with: "_") }

    public func foodFactor(group: String) -> FoodFactor? { foods[Self.key(group)] }
    public func fiberFactor(material: String) -> FiberFactor? { fibers[Self.key(material)] }
    public func endOfLife(material: String) -> MaterialEndOfLife? { materials[Self.key(material)] }
    public func deviceDefaults(deviceType: String) -> DeviceDefaults? { devices[Self.key(deviceType)] }
    public func gridIntensity(region: String) -> RegionalGridIntensity? { grids[region] ?? grids[region.uppercased()] }
    public func perCapita(region: String) -> PerCapitaBaseline? { perCapitas[region.uppercased()] }
    public func asusPCF(model: String) -> ASUSPCFRecord? { asus[model.lowercased()] }
}
