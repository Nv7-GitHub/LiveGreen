import Foundation
import GreenCore

/// The three canned demo scenes (spec §11): desk setup, meal, e-bike corner.
public enum DemoScene: String, CaseIterable, Sendable {
    case deskSetup
    case meal
    case eBikeCorner

    public var title: String {
        switch self {
        case .deskSetup: "Desk setup"
        case .meal: "Lunch"
        case .eBikeCorner: "E-bike corner"
        }
    }

    public var identifyResponse: IdentifyResponse {
        switch self {
        case .deskSetup: DemoFixtures.desk
        case .meal: DemoFixtures.meal
        case .eBikeCorner: DemoFixtures.eBike
        }
    }
}

private func est(_ value: Double, _ low: Double, _ high: Double) -> EstimateRange {
    EstimateRange(value: value, low: low, high: high)
}

enum DemoFixtures {
    static let hoursQuestion = ComponentQuestion(
        id: "hours_on",
        question: "How many hours a day is it on?",
        whyItMatters: "Use-phase electricity dominates this device's yearly footprint.",
        affectedMetrics: [.carbon, .yearlyElectricity],
        options: [
            AnswerOption(label: "~2 h", field: .hoursOnPerDay, value: 2),
            AnswerOption(label: "~6 h", field: .hoursOnPerDay, value: 6),
            AnswerOption(label: "~10 h", field: .hoursOnPerDay, value: 10),
        ])

    static let desk = IdentifyResponse(components: [
        IdentifiedComponent(
            name: "ASUS Zenbook 14 laptop", category: .electronic,
            boundingBox: NormalizedRect(x: 0.30, y: 0.45, width: 0.40, height: 0.32),
            identifiers: Identifiers(brand: "ASUS", model: "UX3405MA"),
            quantities: Quantities(massKg: 1.2, screenSizeInches: 14, ratedPowerW: 65, deviceType: "laptop"),
            defaultUsage: UsageProfile(hoursOnPerDay: 8, standbyHoursPerDay: 16),
            deferrableLoad: .laptopCharger,
            estimates: [.carbon: est(260, 180, 380), .powerOn: est(30, 15, 45), .standbyPower: est(1, 0.5, 2),
                        .yearlyElectricity: est(60, 35, 95), .lifespan: est(4, 3, 6), .repairability: est(5, 3, 7),
                        .plasticMass: est(350, 200, 500), .recyclablePercent: est(60, 40, 80)]),
        IdentifiedComponent(
            name: "27-inch monitor", category: .electronic,
            boundingBox: NormalizedRect(x: 0.25, y: 0.08, width: 0.50, height: 0.34),
            identifiers: Identifiers(brand: "Dell", model: "S2721H"),
            quantities: Quantities(massKg: 3.6, screenSizeInches: 27, deviceType: "monitor"),
            defaultUsage: UsageProfile(hoursOnPerDay: 8, standbyHoursPerDay: 16),
            estimates: [.carbon: est(400, 250, 650), .powerOn: est(25, 15, 40), .standbyPower: est(0.3, 0.2, 0.5),
                        .yearlyElectricity: est(70, 30, 120), .lifespan: est(6, 4, 8), .repairability: est(4, 2, 6),
                        .plasticMass: est(1800, 1200, 2500), .recyclablePercent: est(55, 40, 70)],
            needsQuestion: [hoursQuestion]),
        IdentifiedComponent(
            name: "Disposable coffee cup", category: .packaging,
            boundingBox: NormalizedRect(x: 0.78, y: 0.52, width: 0.12, height: 0.20),
            identifiers: Identifiers(materials: [MaterialShare(material: "paperboard", percent: 95),
                                                 MaterialShare(material: "polyethylene", percent: 5)]),
            quantities: Quantities(massKg: 0.012, packagingMassG: 12),
            defaultUsage: UsageProfile(usesPerWeek: 5),
            estimates: [.carbon: est(0.11, 0.06, 0.2), .water: est(1.5, 0.8, 3), .plasticMass: est(3.5, 2, 5),
                        .recyclablePercent: est(5, 0, 20), .decompositionTime: est(30, 20, 50)]),
        IdentifiedComponent(
            name: "LED desk lamp", category: .electronic,
            boundingBox: NormalizedRect(x: 0.05, y: 0.20, width: 0.16, height: 0.50),
            quantities: Quantities(massKg: 0.8, ratedPowerW: 8, deviceType: "led_lamp"),
            defaultUsage: UsageProfile(hoursOnPerDay: 4, standbyHoursPerDay: 20),
            estimates: [.carbon: est(15, 8, 25), .powerOn: est(8, 5, 12), .standbyPower: est(0.4, 0.2, 0.8),
                        .yearlyElectricity: est(15, 8, 25), .lifespan: est(10, 6, 15), .repairability: est(6, 4, 8),
                        .plasticMass: est(200, 100, 350), .recyclablePercent: est(50, 30, 70)]),
    ], sceneTitle: "Desk setup")

    static let meal = IdentifyResponse(components: [
        IdentifiedComponent(
            name: "Beef burger", category: .food,
            boundingBox: NormalizedRect(x: 0.20, y: 0.30, width: 0.40, height: 0.35),
            quantities: Quantities(massKg: 0.25, servingKg: 0.12, foodGroup: "beef"),
            defaultUsage: UsageProfile(servingsPerWeek: 2),
            estimates: [.carbon: est(7.2, 4, 12), .water: est(170, 90, 300), .land: est(39, 20, 60),
                        .waterPollution: est(36, 20, 60), .plasticMass: est(4, 1, 8),
                        .recyclablePercent: est(10, 0, 30), .decompositionTime: est(0.1, 0.05, 0.3)],
            needsQuestion: [ComponentQuestion(
                id: "servings", question: "How often do you eat this?",
                whyItMatters: "Beef is the largest contributor here, so frequency sets the yearly total.",
                affectedMetrics: [.carbon, .land, .water],
                options: [AnswerOption(label: "Rarely", field: .servingsPerWeek, value: 0.25),
                          AnswerOption(label: "Weekly", field: .servingsPerWeek, value: 1),
                          AnswerOption(label: "Most days", field: .servingsPerWeek, value: 5)])]),
        IdentifiedComponent(
            name: "French fries", category: .food,
            boundingBox: NormalizedRect(x: 0.62, y: 0.38, width: 0.25, height: 0.25),
            quantities: Quantities(massKg: 0.15, servingKg: 0.15, foodGroup: "potatoes"),
            defaultUsage: UsageProfile(servingsPerWeek: 2),
            estimates: [.carbon: est(0.5, 0.3, 0.9), .water: est(9, 4, 16), .land: est(0.13, 0.08, 0.25),
                        .waterPollution: est(0.5, 0.3, 1), .plasticMass: est(1, 0, 3),
                        .recyclablePercent: est(20, 0, 50), .decompositionTime: est(0.1, 0.05, 0.3)]),
        IdentifiedComponent(
            name: "Cola can", category: .food,
            boundingBox: NormalizedRect(x: 0.05, y: 0.20, width: 0.13, height: 0.35),
            identifiers: Identifiers(gtin: "5449000000996", brand: "Coca-Cola"),
            quantities: Quantities(massKg: 0.345, packagingMassG: 13, volumeLiters: 0.33, foodGroup: "soft_drinks"),
            defaultUsage: UsageProfile(servingsPerWeek: 3),
            estimates: [.carbon: est(0.17, 0.1, 0.3), .water: est(2, 1, 5), .land: est(0.05, 0.02, 0.1),
                        .waterPollution: est(0.2, 0.1, 0.4), .plasticMass: est(0.5, 0.2, 1),
                        .recyclablePercent: est(70, 50, 90), .decompositionTime: est(200, 80, 500)]),
        // No material identified, so its carbon stays a T4 estimate and the scan asks what it is made of.
        IdentifiedComponent(
            name: "Takeout box", category: .packaging,
            boundingBox: NormalizedRect(x: 0.62, y: 0.68, width: 0.30, height: 0.22),
            quantities: Quantities(packagingMassG: 30),
            defaultUsage: UsageProfile(usesPerWeek: 2),
            estimates: [.carbon: est(0.08, 0.03, 0.2), .water: est(1, 0.3, 3), .plasticMass: est(10, 0, 30),
                        .recyclablePercent: est(15, 0, 50), .decompositionTime: est(100, 1, 500)]),
    ], sceneTitle: "Lunch")

    static let eBike = IdentifyResponse(components: [
        IdentifiedComponent(
            name: "E-bike", category: .electronic,
            boundingBox: NormalizedRect(x: 0.10, y: 0.15, width: 0.60, height: 0.70),
            quantities: Quantities(massKg: 24, deviceType: "ebike"),
            // Battery charging energy is counted here; the charger below only adds its idle draw.
            defaultUsage: UsageProfile(chargesPerWeek: 3),
            deferrableLoad: .eBike,
            estimates: [.carbon: est(165, 120, 250), .powerOn: est(250, 200, 350), .standbyPower: est(0, 0, 0.1),
                        .yearlyElectricity: est(80, 40, 140), .lifespan: est(8, 5, 12), .repairability: est(7, 5, 9),
                        .plasticMass: est(2500, 1500, 4000), .recyclablePercent: est(75, 60, 90)]),
        IdentifiedComponent(
            name: "E-bike battery charger", category: .electronic,
            boundingBox: NormalizedRect(x: 0.72, y: 0.62, width: 0.18, height: 0.15),
            quantities: Quantities(massKg: 0.6, ratedPowerW: 170, deviceType: "ebike_charger"),
            defaultUsage: UsageProfile(hoursOnPerDay: 0, standbyHoursPerDay: 24),
            estimates: [.carbon: est(6, 3, 10), .powerOn: est(170, 120, 200), .standbyPower: est(0.5, 0.2, 1),
                        .yearlyElectricity: est(4, 2, 9), .lifespan: est(6, 4, 9), .repairability: est(3, 1, 5),
                        .plasticMass: est(250, 150, 400), .recyclablePercent: est(40, 20, 60)]),
        IdentifiedComponent(
            name: "Power strip", category: .electronic,
            boundingBox: NormalizedRect(x: 0.70, y: 0.82, width: 0.25, height: 0.10),
            quantities: Quantities(massKg: 0.5, deviceType: "power_strip"),
            defaultUsage: UsageProfile(hoursOnPerDay: 24),
            estimates: [.carbon: est(4, 2, 7), .powerOn: est(0.5, 0.2, 1), .standbyPower: est(0.5, 0.2, 1),
                        .yearlyElectricity: est(4, 2, 9), .lifespan: est(10, 6, 15), .repairability: est(2, 1, 4),
                        .plasticMass: est(300, 200, 450), .recyclablePercent: est(30, 15, 50)]),
    ], sceneTitle: "E-bike corner")
}
