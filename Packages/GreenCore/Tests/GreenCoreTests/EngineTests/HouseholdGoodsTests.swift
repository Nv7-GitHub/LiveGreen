import Foundation
import Testing
@testable import GreenCore

/// Household goods: made goods carry their processing (D2), consumables are counted by how many are used up (D3),
/// and only electronics are matched to device records by name (D4).
@Suite("Household goods")
struct HouseholdGoodsTests {
    let store = ReferenceStore.bundled
    let engine = ImpactEngine(reference: ReferenceStore.bundled)
    let resolver = FactorModelResolver(store: .bundled)

    func share(_ material: String, _ percent: Double) -> MaterialShare { MaterialShare(material: material, percent: percent) }

    func resolved(_ component: Component) -> Component {
        var result = component
        let output = resolver.household(component)
        result.metrics = output.metrics
        result.stageShares = output.stageShares
        return result
    }

    @Test func aBikeCarriesItsMakingAndAnHonestSplit() throws {
        let bike = resolved(Component(name: "Silver city bike", category: .household,
                                      identifiers: Identifiers(materials: [share("aluminium", 40), share("steel", 45),
                                                                           share("rubber", 10), share("other_plastic", 5)]),
                                      quantities: Quantities(massKg: 15)))
        let materials = 15 * (0.40 * 8.6 + 0.45 * 2.0 + 0.10 * 2.7 + 0.05 * 2.5)
        let carbon = try #require(bike.metrics[.carbon])
        #expect(abs(carbon.value - materials / 0.55) < 1e-9)
        #expect((100...150).contains(carbon.value), "≈120 kg for a bike, not the 57-79 kg of its materials alone")
        #expect(carbon.sources.contains(FactorModelResolver.processingSource))
        // The split says what was computed: materials are their own share, and nothing is "use" for a pedal bike.
        #expect(abs((bike.stageShares[.materials] ?? 0) - 0.55) < 1e-9)
        #expect(bike.stageShares[.use] == nil)
        #expect(abs(bike.stageShares.values.reduce(0, +) - 1) < 1e-9)
        // A bike lasts about 10 years, so its year is not doubled by the 5-year default.
        #expect(engine.lifespan(of: bike).value == 10)
        #expect(abs(try #require(engine.yearly(.carbon, of: bike)).value - carbon.value / 10) < 1e-6)
    }

    @Test func unpoweredGoodsHaveNoUseStage() {
        #expect(StageModel.defaultCarbonShares(for: .household)[.use] == nil)
        let mug = Component(name: "Mug", category: .household)
        #expect(engine.stageShares(for: mug)[.use] == nil)
    }

    @Test func aSprayIsCountedByTheBottlesUsedUp() throws {
        // Shout spray: about 80 treatments a bottle, used 3 times a week, is about 2 bottles a year, not a fifth of one.
        var spray = resolved(Component(name: "Shout stain remover spray", category: .household,
                                       identifiers: Identifiers(materials: [share("detergent_formula", 100)],
                                                                packagingMaterials: [share("hdpe", 70), share("pp", 30)]),
                                       quantities: Quantities(massKg: 0.72, packagingMassG: 55, volumeLiters: 0.65,
                                                              consumable: true, usesPerContainer: 80),
                                       usage: UsageProfile(usesPerWeek: 3)))
        guard case .unitsPerYear(let bottles) = engine.annualBasis(for: spray) else { Issue.record("still a durable"); return }
        #expect(abs(bottles - 3 * 52 / 80) < 1e-9)
        let perBottle = try #require(spray.metrics[.carbon]).value
        #expect(abs(try #require(engine.yearly(.carbon, of: spray)).value - perBottle * bottles) < 1e-9)
        #expect(engine.carbonViews(of: spray)?.lifetime == nil)
        #expect(spray.metrics[.lifespan] == nil)
        // How often it is used is what the year assumes, and it can be edited.
        #expect(engine.usageAssumption(for: spray) == .usesPerWeek(3))
        #expect(engine.editableUsage(for: spray).map(\.field) == [.usesPerWeek])
        spray = engine.applyingUsage(UsageProfile(usesPerWeek: 6), to: spray, profile: .default)
        #expect(abs(try #require(engine.yearly(.carbon, of: spray)).value - perBottle * 2 * bottles) < 1e-9)
        // Without a count from identify, one lasts the default number of uses.
        let unknown = Component(name: "Sponge", category: .household, quantities: Quantities(consumable: true))
        #expect(abs(engine.consumablesPerYear(of: unknown) - 52 / ImpactEngine.defaultUsesPerContainer) < 1e-9)
    }

    @Test func aPaperNotebookIsNotALaptop() throws {
        let notebook = Component(name: "Spiral notebook (Mead Five Star)", category: .household,
                                 identifiers: Identifiers(materials: [share("paper", 70), share("pp", 18), share("steel", 12)]),
                                 quantities: Quantities(massKg: 0.28))
        #expect(store.deviceProfile(for: notebook) == nil)
        #expect(store.deviceProfile(deviceType: "notebook") == nil, "no bare notebook alias")
        let durable = resolved(notebook)
        #expect(durable.metrics[.lifespan] == nil)
        #expect(!engine.lifespan(of: durable).sources.contains { $0.title.contains("Dell") })
        // Filled in a semester or two, it is a consumable when identify says so.
        var used = notebook
        used.quantities.consumable = true
        used.quantities.usesPerContainer = 60
        used.usage = UsageProfile(usesPerWeek: 2)
        guard case .unitsPerYear(let perYear) = engine.annualBasis(for: used) else { Issue.record("still a durable"); return }
        #expect(abs(perYear - 2 * 52 / 60) < 1e-9)
        // A laptop is still found by its name or device type.
        let laptop = Component(name: "Notebook computer", category: .electronic)
        #expect(store.deviceProfile(for: laptop)?.defaults.deviceType == "laptop")
        #expect(store.deviceProfile(for: Component(name: "Thing", category: .household,
                                                   quantities: Quantities(deviceType: "laptop"))) != nil)
    }
}
