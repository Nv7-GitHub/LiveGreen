import Foundation
import GreenCore
import GreenCoreFakes

/// A richly resolved desk-setup scan for previews: the demo fixture's components with a sample
/// photo, mixed T1–T4 evidence, citations and a recorded stage split.
enum ResultSamples {
    static let desk: ScanResult = makeDesk()

    private static let energyStar = Source(
        title: "ENERGY STAR certified displays dataset",
        url: URL(string: "https://data.energystar.gov/"),
        tier: .exactRecord)
    private static let asusPCF = Source(
        title: "ASUS product carbon footprint report",
        url: URL(string: "https://esg.asus.com/"),
        tier: .exactRecord)
    private static let asusSpecs = Source(
        title: "ASUS Zenbook 14 OLED (UX3405) tech specs",
        url: URL(string: "https://www.asus.com/laptops/for-home/zenbook/"),
        tier: .researchedSpec,
        quote: "65W USB Type-C power adapter")
    private static let deviceDefaults = Source(
        title: "Typical device figures (ENERGY STAR / EU repairability averages)",
        url: URL(string: "https://www.energystar.gov/products"),
        tier: .factorModel)
    private static let paperCup = Source(
        title: "Paper and paperboard: material-specific data (US EPA)",
        url: URL(string: "https://www.epa.gov/facts-and-figures-about-materials-waste-and-recycling/paper-and-paperboard-material-specific-data"),
        tier: .factorModel)
    private static let estimate = Source(title: "Claude estimate from the photo", tier: .estimate)

    private static func makeDesk() -> ScanResult {
        var components = DemoScene.deskSetup.identifyResponse.components.map { $0.makeComponent() }
        guard components.count == 4 else {
            return ScanResult(title: "Desk setup", photo: SamplePhoto.deskJPEG(), components: components,
                              totals: ScanTotals.sum(components))
        }

        // Laptop: ASUS PCF record (T1) with a stage split, researched adapter rating (T2), factor-model rest.
        components[0].metrics = [
            .carbon: Measured(value: 238, low: 214, high: 262, unit: .kgCO2e, tier: .exactRecord, sources: [asusPCF]),
            .powerOn: Measured(value: 28, relativeRange: 0.1, unit: .watts, tier: .researchedSpec, sources: [asusSpecs]),
            .standbyPower: Measured(value: 0.9, low: 0.5, high: 1.4, unit: .watts, tier: .factorModel, sources: [deviceDefaults]),
            .yearlyElectricity: Measured(value: 87, low: 60, high: 115, unit: .kilowattHoursPerYear, tier: .factorModel,
                                         sources: [asusSpecs, deviceDefaults]),
            .lifespan: Measured(value: 4, low: 3, high: 6, unit: .years, tier: .factorModel, sources: [deviceDefaults]),
            .repairability: Measured(value: 5, low: 3, high: 7, unit: .score10, tier: .estimate, sources: [estimate]),
            .plasticMass: Measured(value: 350, low: 175, high: 525, unit: .grams, tier: .estimate, sources: [estimate]),
            .recyclablePercent: Measured(value: 60, low: 40, high: 80, unit: .percent, tier: .estimate, sources: [estimate]),
        ]
        components[0].stageShares = [.materials: 0.38, .manufacturing: 0.36, .transport: 0.04, .use: 0.21, .endOfLife: 0.01]
        components[0].plugCandidate = PlugCandidate(loadType: .laptopCharger, chargerWatts: 65, dailyKWh: 87.0 / 365)

        // Monitor: ENERGY STAR record for power (T1) but only an estimate for carbon, which leaves a wide
        // range on a top contributor, so the hours-on question passes the gate.
        components[1].metrics = [
            .carbon: Measured(value: 400, low: 250, high: 650, unit: .kgCO2e, tier: .estimate, sources: [estimate]),
            .powerOn: .exact(17.9, unit: .watts, tier: .exactRecord, sources: [energyStar]),
            .standbyPower: .exact(0.3, unit: .watts, tier: .exactRecord, sources: [energyStar]),
            .yearlyElectricity: .exact(56, unit: .kilowattHoursPerYear, tier: .exactRecord, sources: [energyStar]),
            .lifespan: Measured(value: 6, low: 4, high: 8, unit: .years, tier: .factorModel, sources: [deviceDefaults]),
            .repairability: Measured(value: 4, low: 2, high: 6, unit: .score10, tier: .estimate, sources: [estimate]),
            .plasticMass: Measured(value: 1800, low: 900, high: 2700, unit: .grams, tier: .estimate, sources: [estimate]),
            .recyclablePercent: Measured(value: 55, low: 40, high: 70, unit: .percent, tier: .factorModel, sources: [deviceDefaults]),
        ]

        // Cup: factor model from material tables (T3).
        components[2].metrics = [
            .carbon: Measured(value: 0.11, low: 0.08, high: 0.15, unit: .kgCO2e, tier: .factorModel, sources: [paperCup]),
            .water: Measured(value: 1.5, low: 1, high: 2.2, unit: .liters, tier: .factorModel, sources: [paperCup]),
            .plasticMass: Measured(value: 0.6, low: 0.4, high: 0.8, unit: .grams, tier: .factorModel, sources: [paperCup]),
            .recyclablePercent: Measured(value: 5, low: 0, high: 15, unit: .percent, tier: .factorModel, sources: [paperCup]),
            .decompositionTime: Measured(value: 30, low: 20, high: 50, unit: .years, tier: .factorModel, sources: [paperCup]),
        ]

        // Lamp: device defaults (T3) plus wide estimates (T4).
        components[3].metrics = [
            .carbon: Measured(value: 15, low: 7.5, high: 25, unit: .kgCO2e, tier: .estimate, sources: [estimate]),
            .powerOn: Measured(value: 8, relativeRange: 0.2, unit: .watts, tier: .factorModel, sources: [deviceDefaults]),
            .standbyPower: Measured(value: 0.4, low: 0.2, high: 0.8, unit: .watts, tier: .factorModel, sources: [deviceDefaults]),
            .yearlyElectricity: Measured(value: 14.6, low: 9, high: 22, unit: .kilowattHoursPerYear, tier: .factorModel,
                                         sources: [deviceDefaults]),
            .lifespan: Measured(value: 10, low: 6, high: 15, unit: .years, tier: .factorModel, sources: [deviceDefaults]),
            .plasticMass: Measured(value: 200, low: 100, high: 350, unit: .grams, tier: .estimate, sources: [estimate]),
        ]

        return ScanResult(title: "Desk setup", mode: .photo, photo: SamplePhoto.deskJPEG(),
                          components: components, totals: ScanTotals.sum(components))
    }
}
