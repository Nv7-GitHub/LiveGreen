import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Derived values added after the ladder: use-phase carbon, appliance categories, hints and plug candidates.
@Suite("Scan pipeline derived values")
struct ScanPipelineDerivedTests {
    private struct FixedVision: VisionIdentifier {
        var components: [IdentifiedComponent]
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
            IdentifyResponse(components: components, sceneTitle: nil)
        }
    }

    private func pipeline(_ components: [IdentifiedComponent], extra: [any MetricResolver] = []) -> ScanPipeline {
        let store = ReferenceStore.bundled
        let resolvers = extra + [FactorModelResolver(store: store), EstimateResolver()]
        return ScanPipeline(vision: FixedVision(components: components), alternatives: FakeAlternativeSuggester(),
                            products: FakeProductDatabase(), ladder: EvidenceLadder(resolvers: resolvers),
                            engine: ImpactEngine(reference: store), profile: .default)
    }

    private let tv = IdentifiedComponent(name: "TV", category: .electronic, boundingBox: .full,
                                         identifiers: Identifiers(brand: "Acme", model: "X1"),
                                         quantities: Quantities(deviceType: "tv"))

    @Test func researchedElectronicsCarbonGetsTheUsePhase() async throws {
        let pcf = FakeMetricResolver(tier: .researchedSpec, name: "PCF", values: [.carbon: 100])
        let pipeline = pipeline([tv], extra: [pcf])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let component = try #require(result.components.first)
        let carbon = try #require(component.metrics[.carbon])
        let electricity = try #require(component.metrics[.yearlyElectricity])
        let kWh = electricity.value
        let lifespan = pipeline.engine.lifespan(of: component).value
        let use = ImpactEngine.useCarbon(kWh: kWh, gramsPerKWh: pipeline.engine.gridGramsPerKWh(for: .default)) * lifespan
        #expect(abs(carbon.value - (100 + use)) < 1e-6)
        // The weaker of the two evidence tiers that went into the number.
        #expect(carbon.tier == max(.researchedSpec, electricity.tier))
        #expect(carbon.low < carbon.value && carbon.value < carbon.high)
        let useShare = try #require(component.stageShares[.use])
        #expect(abs(useShare - use / (100 + use)) < 1e-9)
    }

    @Test func factorModelCarbonIsNotDoubleCounted() async throws {
        let unidentified = IdentifiedComponent(name: "TV", category: .electronic, boundingBox: .full,
                                               quantities: Quantities(deviceType: "tv"))
        let pipeline = pipeline([unidentified])
        let component = try #require(try await pipeline.run(image: Data([1]), hints: .none, mode: .photo).components.first)
        let direct = FactorModelResolver(store: .bundled).electronic(component, profile: .default)
        #expect(component.metrics[.carbon]?.tier == .factorModel)
        #expect(component.metrics[.carbon]?.value == direct.metrics[.carbon]?.value)
    }

    @Test func pluggedInHouseholdItemsAreElectronics() async throws {
        let dishwasher = IdentifiedComponent(name: "Dishwasher", category: .household, boundingBox: .full,
                                             quantities: Quantities(deviceType: "dishwasher"))
        let component = try #require(try await pipeline([dishwasher]).run(image: Data([1]), hints: .none, mode: .photo)
            .components.first)
        #expect(component.category == .electronic)
        #expect(component.metrics[.yearlyElectricity] != nil)
        #expect(component.plugCandidate?.loadType == .dishwasher)
    }

    @Test func explicitDeferrableLoadsSkipTheMinimum() async throws {
        let bank = IdentifiedComponent(name: "Power bank", category: .electronic, boundingBox: .full,
                                       quantities: Quantities(deviceType: "power_bank"),
                                       defaultUsage: UsageProfile(chargesPerWeek: 2), deferrableLoad: .powerBank)
        let component = try #require(try await pipeline([bank]).run(image: Data([1]), hints: .none, mode: .photo)
            .components.first)
        let electricity = try #require(component.metrics[.yearlyElectricity])
        let kWh = electricity.value
        #expect(kWh < ScanPipeline.minimumPlugKWhPerYear)
        #expect(component.plugCandidate?.loadType == .powerBank)
    }

    @Test func unambiguousHintsBecomeIdentifiers() {
        let hints = OCRHints(gtins: ["5449000000996"], modelNumbers: ["S2721H"], wattages: [65],
                             fiberPercentages: [MaterialShare(material: "cotton", percent: 100)])
        let components = [
            IdentifiedComponent(name: "Cola", category: .food, boundingBox: .full),
            IdentifiedComponent(name: "Monitor", category: .electronic, boundingBox: .full),
            IdentifiedComponent(name: "T-shirt", category: .clothing, boundingBox: .full),
        ]
        let merged = ScanPipeline.applyingHints(hints, to: components)
        #expect(merged[0].identifiers.gtin == "5449000000996")
        #expect(merged[1].identifiers.model == "S2721H")
        #expect(merged[1].quantities.ratedPowerW == 65)
        #expect(merged[2].identifiers.materials.map(\.material) == ["cotton"])

        // Two electronics: the model number could belong to either, so it is left to the model.
        let two = ScanPipeline.applyingHints(hints, to: [components[1], components[1]])
        #expect(two.allSatisfy { $0.identifiers.model == nil })
        // Identifiers the model already set are kept.
        var labeled = components[1]
        labeled.identifiers.model = "U2723QE"
        #expect(ScanPipeline.applyingHints(hints, to: [labeled])[0].identifiers.model == "U2723QE")
    }
}
