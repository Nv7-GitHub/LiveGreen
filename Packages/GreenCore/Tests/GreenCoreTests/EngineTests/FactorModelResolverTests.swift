import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Factor model and ASUS resolvers")
struct FactorModelResolverTests {
    let resolver = FactorModelResolver()

    func resolve(_ component: Component, profile: UserProfile = .default) async throws -> ResolverOutput {
        try await resolver.resolve(ResolutionRequest(component: component, metrics: Set(MetricKey.allCases), profile: profile))
    }

    @Test func foodPerServing() async throws {
        let burger = Component(name: "Beef burger", category: .food, quantities: Quantities(servingKg: 0.12, foodGroup: "beef"))
        let output = try await resolve(burger)
        let carbon = try #require(output.metrics[.carbon])
        #expect(abs(carbon.value - 99.48 * 0.12) < 1e-9)
        #expect(abs(carbon.spreadRatio - 1.6 * 1.6) < 1e-9)
        #expect(carbon.tier == .factorModel)
        #expect(carbon.sources.first?.title.contains("Poore") == true)
        #expect(abs(try #require(output.metrics[.water]).value - 1451.2 * 0.12) < 1e-9)
        #expect(try #require(output.metrics[.plasticMass]).value == 0) // unpackaged
        #expect(abs(output.stageShares.values.reduce(0, +) - 1) < 0.01)
    }

    @Test func packagingFromMaterials() async throws {
        let cup = Component(name: "Coffee cup", category: .packaging,
                            identifiers: Identifiers(materials: [MaterialShare(material: "paperboard", percent: 95),
                                                                 MaterialShare(material: "polyethylene", percent: 5)]),
                            quantities: Quantities(packagingMassG: 12))
        let output = try await resolve(cup)
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 0.6) < 1e-9)
        #expect(abs(try #require(output.metrics[.recyclablePercent]).value - (0.95 * 68.2 + 0.05 * 4.0)) < 1e-9)
        // The 5% polyethylene lining (20 years) outlasts the paperboard.
        #expect(try #require(output.metrics[.decompositionTime]).value == 20)
        #expect(abs(try #require(output.metrics[.carbon]).value - (0.95 * 0.012 * 1.1 + 0.05 * 0.012 * 1.9)) < 1e-9)
    }

    @Test func unknownMaterialsGiveNothing() async throws {
        let mystery = Component(name: "Thing", category: .packaging,
                                identifiers: Identifiers(materials: [MaterialShare(material: "unobtainium", percent: 100)]),
                                quantities: Quantities(packagingMassG: 50))
        #expect(try await resolve(mystery).metrics.isEmpty)
    }

    @Test func electronicsScaleWithScreenAndIncludeUsePhase() async throws {
        let monitor = Component(name: "27-inch monitor", category: .electronic,
                                quantities: Quantities(screenSizeInches: 27, deviceType: "monitor"),
                                usage: UsageProfile(hoursOnPerDay: 8, standbyHoursPerDay: 16))
        let output = try await resolve(monitor)
        let scale = pow(27.0 / 24.0, 2)
        let power = try #require(output.metrics[.powerOn])
        #expect(abs(power.value - 18 * scale) < 1e-9)
        let kWh = try #require(output.metrics[.yearlyElectricity])
        #expect(abs(kWh.value - (18 * scale * 8 + 0.3 * 16) * 365 / 1000) < 1e-9)
        let carbon = try #require(output.metrics[.carbon])
        let expected = 300 * scale + kWh.value * 246.4 / 1000 * 6
        #expect(abs(carbon.value - expected) < 1e-6)
        #expect(carbon.low < carbon.value && carbon.high > carbon.value)
        #expect((output.stageShares[.use] ?? 0) > 0)
        #expect(abs(output.stageShares.values.reduce(0, +) - 1) < 1e-9)
    }

    @Test func betterTierPowerFeedsDerivedMetrics() async throws {
        var monitor = Component(name: "Monitor", category: .electronic, quantities: Quantities(deviceType: "monitor"),
                                usage: UsageProfile(hoursOnPerDay: 10, standbyHoursPerDay: 14))
        monitor.metrics[.powerOn] = .exact(15, unit: .watts, tier: .exactRecord)
        let output = try await resolver.resolve(ResolutionRequest(component: monitor, metrics: [.yearlyElectricity, .carbon],
                                                                  profile: .default))
        #expect(output.metrics[.powerOn] == nil) // not requested
        #expect(abs(try #require(output.metrics[.yearlyElectricity]).value - (15 * 10 + 0.3 * 14) * 365 / 1000) < 1e-9)
    }

    @Test func clothingFromFibers() async throws {
        let shirt = Component(name: "T-shirt", category: .clothing,
                              identifiers: Identifiers(materials: [MaterialShare(material: "cotton", percent: 60),
                                                                   MaterialShare(material: "polyester", percent: 40)]),
                              quantities: Quantities(massKg: 0.2))
        let output = try await resolve(shirt)
        #expect(abs(try #require(output.metrics[.carbon]).value - 0.2 * (0.6 * 1.8 + 0.4 * 3.4 + 11.0)) < 1e-9)
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 80) < 1e-9)
        #expect(try #require(output.metrics[.lifespan]).value == 3.3)
        #expect(try #require(output.metrics[.decompositionTime]).value == 200)
    }

    @Test func asusRecordWinsForMatchingModel() async throws {
        let laptop = Component(name: "Zenbook", category: .electronic, identifiers: Identifiers(brand: "ASUS", model: "UX3405MA"))
        let output = try await ASUSPCFResolver().resolve(ResolutionRequest(component: laptop, metrics: Set(MetricKey.allCases),
                                                                           profile: .default))
        let carbon = try #require(output.metrics[.carbon])
        #expect(carbon.value == 210 && carbon.tier == .exactRecord)
        #expect(carbon.sources.first?.url?.absoluteString.contains("UX3405M") == true)
        #expect(output.metrics[.lifespan]?.value == 4)
        #expect(abs((output.stageShares[.manufacturing] ?? 0) - 0.766) < 0.001)

        let dell = Component(name: "Dell", category: .electronic, identifiers: Identifiers(brand: "Dell", model: "UX3405MA"))
        let none = try await ASUSPCFResolver().resolve(ResolutionRequest(component: dell, metrics: [.carbon], profile: .default))
        #expect(none.metrics.isEmpty)
    }

    @Test func demoScenesResolveThroughFullLadder() async {
        let ladder = EvidenceLadder(resolvers: SampleScans.demoRecordResolvers + [ASUSPCFResolver(), resolver, EstimateResolver()])
        for scene in DemoScene.allCases {
            for identified in scene.identifyResponse.components {
                let component = await ladder.resolve(identified.makeComponent(), profile: .default)
                #expect(component.missingMetrics.isEmpty, "\(scene) \(component.name) missing \(component.missingMetrics)")
                for (metric, measured) in component.metrics {
                    #expect(measured.unit == metric.unit, "\(component.name) \(metric) unit")
                    #expect(measured.value.isFinite && measured.low <= measured.value && measured.value <= measured.high)
                }
            }
        }
        let laptop = await ladder.resolve(DemoScene.deskSetup.identifyResponse.components[0].makeComponent(), profile: .default)
        #expect(laptop.metrics[.carbon]?.tier == .exactRecord)
        #expect(laptop.metrics[.repairability]?.tier == .factorModel)
    }
}
