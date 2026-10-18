import Foundation
import Testing
@testable import GreenCore

@Suite("Materials and household products")
struct MaterialRowsTests {
    let store = ReferenceStore.bundled
    let resolver = FactorModelResolver(store: .bundled)
    /// What is made from a material also carries its forming, assembly, transport and disposal; a used-up formula does not.
    let made = 1 / FactorModelResolver.materialsShare

    func share(_ material: String, _ percent: Double) -> MaterialShare { MaterialShare(material: material, percent: percent) }

    func household(_ name: String, kg: Double, _ materials: [MaterialShare], packagingG: Double? = nil,
                   packaging: [MaterialShare]? = nil, liters: Double? = nil) -> ResolverOutput {
        resolver.household(Component(name: name, category: .household,
                                     identifiers: Identifiers(materials: materials, packagingMaterials: packaging),
                                     quantities: Quantities(massKg: kg, packagingMassG: packagingG, volumeLiters: liters)))
    }

    @Test func swapKeysExistAndFoodIsNotAMaterial() {
        let vocabulary = store.vocabulary.materials
        for key in ["stainless_steel", "ceramic", "glass_tableware", "pet_thermoform", "detergent_formula"] {
            #expect(store.materialFactor(material: key)?.endOfLife.material == key, "\(key) row")
            #expect(vocabulary.contains(key), "\(key) offered to identify")
        }
        #expect(!vocabulary.contains("food_organic"))
        #expect(store.materialFactor(material: "plastic cup")?.endOfLife.material == "pet_thermoform")
        #expect(store.materialFactor(material: "PET")?.endOfLife.material == "pet")
        #expect(store.materialFactor(resinCode: 1)?.endOfLife.material == "pet")
        #expect(store.materialFactor(material: "stainless steel tumbler")?.endOfLife.material == "stainless_steel")
        #expect(store.materialFactor(material: "steel")?.endOfLife.material == "steel")
    }

    @Test func thermoformedCupsRecycleAtTheirOwnRate() throws {
        let cups = Component(name: "Clear plastic cups", category: .packaging,
                             identifiers: Identifiers(materials: [share("pet_thermoform", 100)]),
                             quantities: Quantities(packagingMassG: 30))
        let output = resolver.packaging(cups)
        #expect(try #require(output.metrics[.recyclablePercent]).value == 4)
        #expect(try #require(output.metrics[.plasticMass]).value == 30)
        #expect(abs(try #require(output.metrics[.carbon]).value - 0.03 * 2.9) < 1e-9)
    }

    @Test func tablewareIsNotContainerGlass() throws {
        let bowl = household("Ceramic bowl", kg: 0.4, [share("ceramic", 100)])
        #expect(abs(try #require(bowl.metrics[.carbon]).value - 1.0 * made) < 1e-9)
        #expect(try #require(bowl.metrics[.recyclablePercent]).value == 0)
        #expect(bowl.metrics[.decompositionTime] == nil, "inert: no decomposition time")
        let glass = household("Drinking glass", kg: 0.3, [share("glass_tableware", 100)])
        #expect(abs(try #require(glass.metrics[.carbon]).value - 0.45 * made) < 1e-9)
        #expect(try #require(glass.metrics[.recyclablePercent]).value == 0)
        let spoon = household("Metal spoon", kg: 0.04, [share("stainless_steel", 100)])
        #expect(abs(try #require(spoon.metrics[.carbon]).value - 0.04 * 6.15 * made) < 1e-9)
        #expect(spoon.metrics[.decompositionTime] == nil)
    }

    @Test func aFilledProductIsItsFormulaPlusItsContainer() throws {
        // A 22 fl oz stain-remover spray: 665 g of formula in a 55 g HDPE bottle with a PP trigger.
        let spray = household("Stain remover spray", kg: 0.72, [share("detergent_formula", 100)], packagingG: 55,
                              packaging: [share("hdpe", 70), share("pp", 30)], liters: 0.65)
        let carbon = 0.665 * 1.0 + (0.0385 * 1.8 + 0.0165 * 1.6) * made
        #expect(abs(try #require(spray.metrics[.carbon]).value - carbon) < 1e-9)
        #expect(abs(try #require(spray.metrics[.plasticMass]).value - 55) < 1e-9)
        // Only the bottle is thrown away: the formula is used up.
        #expect(abs(try #require(spray.metrics[.recyclablePercent]).value - (0.7 * 29.3 + 0.3 * 2.7)) < 1e-9)
        #expect(try #require(spray.metrics[.decompositionTime]).value == 450)
        #expect(spray.plasticPackagingShare == 1)
    }

    @Test func olderAnswersForFilledProductsStillReadSensibly() throws {
        // The liquid tagged as food is the formula, so the product is no longer near zero carbon.
        let tagged = household("Stain remover spray", kg: 0.72, [share("food_organic", 92), share("hdpe", 6), share("pp", 2)],
                               packagingG: 55, liters: 0.65)
        #expect(abs(try #require(tagged.metrics[.carbon]).value - (0.6624 + (0.0432 * 1.8 + 0.0144 * 1.6) * made)) < 1e-9)
        #expect(abs(try #require(tagged.metrics[.plasticMass]).value - 57.6) < 1e-9)
        // Only the bottle described: its split is the bottle's, not 780 g of plastic, and the contents are unknown.
        let bottleOnly = household("Stain remover spray", kg: 0.78,
                                   [share("hdpe", 75), share("pp", 15), share("steel", 2), share("other_plastic", 8)],
                                   packagingG: 55, liters: 0.65)
        #expect(abs(try #require(bottleOnly.metrics[.plasticMass]).value - 55 * 0.98) < 1e-9)
        #expect(bottleOnly.metrics[.carbon] == nil)
    }

    @Test func aDurableInItsBoxCountsBoth() throws {
        let pan = household("Frying pan", kg: 1.2, [share("steel", 100)], packagingG: 200,
                            packaging: [share("corrugated_cardboard", 100)])
        #expect(abs(try #require(pan.metrics[.carbon]).value - (1.0 * 2.0 + 0.2 * 0.9) * made) < 1e-9)
        #expect(abs(try #require(pan.metrics[.recyclablePercent]).value - (1000 * 70.9 + 200 * 96.5) / 1200) < 1e-9)
    }

    @Test func decompositionIsMassWeightedAndSkipsInertMaterials() throws {
        // A few percent of glass used to flip decomposition between 50 and 1,000,000 years.
        let less = household("Shelf", kg: 10, [share("steel", 96), share("glass", 4)])
        let more = household("Shelf", kg: 10, [share("steel", 94), share("glass", 6)])
        #expect(try #require(less.metrics[.decompositionTime]).value == 50)
        #expect(try #require(more.metrics[.decompositionTime]).value == 50)
        let mixed = household("Stool", kg: 2, [share("wood", 50), share("other_plastic", 50)])
        #expect(abs(try #require(mixed.metrics[.decompositionTime]).value - (0.5 * 13 + 0.5 * 500)) < 1e-9)
        // A car is scrapped, not left to break down.
        let car = household("Compact SUV", kg: 1500, [share("steel", 60), share("aluminium", 10), share("other_plastic", 15),
                                                       share("glass", 3), share("rubber", 5), share("electronics_mixed", 7)])
        #expect(car.metrics[.decompositionTime] == nil)
        #expect(try #require(car.metrics[.carbon]).value > 0)
    }

    @Test func unmodelledElectronicsLeaveCarbonToBetterEvidence() throws {
        let gadget = household("Gadget", kg: 5, [share("steel", 70), share("electronics_mixed", 30)])
        #expect(gadget.metrics[.carbon] == nil)
        #expect(gadget.metrics[.plasticMass] != nil)
        // A small unmodelled share is scaled like the rest instead of counting as zero.
        let lamp = household("Floor lamp", kg: 5, [share("steel", 95), share("electronics_mixed", 5)])
        #expect(abs(try #require(lamp.metrics[.carbon]).value - 4.75 * 2.0 / 0.95 * made) < 1e-9)
    }

    @Test func consumedMaterialsLeaveNothingAtEndOfLife() throws {
        let formula = try #require(MaterialBlend(materials: [share("detergent_formula", 100)], massG: 500, store: store))
        #expect(formula.recyclablePercent == nil)
        #expect(formula.decompositionYears == nil)
        #expect(formula.plasticG == 0)
        #expect(abs(formula.kgCO2e - 0.5) < 1e-9)
        #expect(formula.endOfLifeMetrics().keys.sorted { $0.rawValue < $1.rawValue } == [.plasticMass])
    }
}
