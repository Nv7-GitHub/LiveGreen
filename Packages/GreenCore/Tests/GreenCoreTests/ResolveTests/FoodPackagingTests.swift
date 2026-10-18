import Foundation
import Testing
@testable import GreenCore

@Suite("Food packaging and end of life")
struct FoodPackagingTests {
    let resolver = FactorModelResolver(store: .bundled)

    func share(_ material: String, _ percent: Double) -> MaterialShare { MaterialShare(material: material, percent: percent) }

    /// A 28 g serving from a 230 g bag of chips in an 8 g bag.
    func chips(materials: [MaterialShare], packaging: [MaterialShare]?) -> Component {
        Component(name: "Potato chips", category: .food,
                  identifiers: Identifiers(materials: materials, packagingMaterials: packaging),
                  quantities: Quantities(massKg: 0.23, servingKg: 0.028, packagingMassG: 8, foodGroup: "potato_crisps"))
    }

    @Test func packagingMaterialsDescribeThePackageNotTheFood() throws {
        let output = resolver.food(chips(materials: [], packaging: [share("pp", 100)]))
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 8 * 0.028 / 0.23) < 1e-9)
        #expect(try #require(output.metrics[.recyclablePercent]).value == 2.7)
        #expect(try #require(output.metrics[.decompositionTime]).value == 450)
        #expect(output.plasticPackagingShare == 1)
    }

    @Test func olderAnswersLeaveTheFoodOutOfThePackage() throws {
        // The item's own split (96% food, 4% film) used to put 4% of the bag's mass down as plastic.
        let output = resolver.food(chips(materials: [share("food_organic", 96), share("ldpe", 4)], packaging: nil))
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 8 * 0.028 / 0.23) < 1e-9)
        #expect(try #require(output.metrics[.decompositionTime]).value == 20)
        // Nothing but food named: the cup is plastic of unknown kind, not food waste.
        let peach = Component(name: "Peach in plastic cup", category: .food,
                              identifiers: Identifiers(materials: [share("food_organic", 100)]),
                              quantities: Quantities(massKg: 0.15, servingKg: 0.15, packagingMassG: 10, foodGroup: "other_fruit"))
        let cup = resolver.food(peach)
        #expect(abs(try #require(cup.metrics[.plasticMass]).value - 10) < 1e-9)
        #expect(try #require(cup.metrics[.decompositionTime]).value == 500)
    }

    @Test func unpackagedFoodHasNoEndOfLifeFiguresWhateverItsMaterials() throws {
        func apple(_ materials: [MaterialShare]) -> ResolverOutput {
            resolver.food(Component(name: "Apple", category: .food, identifiers: Identifiers(materials: materials),
                                    quantities: Quantities(massKg: 0.18, foodGroup: "apples")))
        }
        let none = apple([]), tagged = apple([share("food_organic", 100)])
        #expect(none == tagged)
        #expect(try #require(none.metrics[.plasticMass]).value == 0)
        #expect(none.metrics[.recyclablePercent] == nil)
        #expect(none.metrics[.decompositionTime] == nil)
    }

    @Test func personalCareContainersIgnoreTheFormula() throws {
        let lotion = Component(name: "Hand lotion", category: .personalCare,
                               identifiers: Identifiers(materials: [share("food_organic", 90), share("hdpe", 10)]),
                               quantities: Quantities(massKg: 0.25, packagingMassG: 30))
        let output = resolver.personalCare(lotion)
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 30) < 1e-9)
        #expect(try #require(output.metrics[.recyclablePercent]).value == 29.3)
    }

    // MARK: Containers counted once

    let drinkBox = NormalizedRect(x: 0.30, y: 0.30, width: 0.20, height: 0.40)
    let cupBox = NormalizedRect(x: 0.28, y: 0.25, width: 0.25, height: 0.50)

    func drink(packagingG: Double?, packaging: [MaterialShare]? = nil, box: NormalizedRect? = nil) -> IdentifiedComponent {
        IdentifiedComponent(name: "Iced latte", category: .food, boundingBox: box ?? drinkBox,
                            identifiers: Identifiers(packagingMaterials: packaging),
                            quantities: Quantities(massKg: 0.45, servingKg: 0.45, packagingMassG: packagingG, foodGroup: "latte"))
    }

    func cup(grams: Double, box: NormalizedRect? = nil) -> IdentifiedComponent {
        IdentifiedComponent(name: "Plastic cup with dome lid", category: .packaging, boundingBox: box ?? cupBox,
                            identifiers: Identifiers(materials: [share("pet_thermoform", 100)]),
                            quantities: Quantities(packagingMassG: grams))
    }

    @Test func aCupReportedTwiceStaysWithTheDrink() {
        let prepared = ScanPipeline.countingContainersOnce([drink(packagingG: 20), cup(grams: 22)], store: .bundled)
        #expect(prepared.map(\.name) == ["Iced latte"])
        #expect(prepared[0].quantities.packagingMassG == 20)
        #expect(prepared[0].identifiers.packagingMaterials == [share("pet_thermoform", 100)])
        // Three cupped foods and one "3 cups" component: the cups are counted once, in the foods.
        let foods = (0..<3).map { index in
            drink(packagingG: 11, box: NormalizedRect(x: 0.1 + Double(index) * 0.3, y: 0.4, width: 0.2, height: 0.3))
        }
        let stack = cup(grams: 36, box: NormalizedRect(x: 0.05, y: 0.35, width: 0.9, height: 0.45))
        #expect(ScanPipeline.countingContainersOnce(foods + [stack], store: .bundled).count == 3)
    }

    @Test func separateContainersStay() {
        // The drink names no packaging, so the cup is its only record.
        #expect(ScanPipeline.countingContainersOnce([drink(packagingG: nil), cup(grams: 22)], store: .bundled).count == 2)
        // A takeout box far heavier than the burger's wrapper is another container.
        let burger = IdentifiedComponent(name: "Burger", category: .food, boundingBox: drinkBox,
                                         quantities: Quantities(massKg: 0.25, packagingMassG: 5, foodGroup: "beef"))
        #expect(ScanPipeline.countingContainersOnce([burger, cup(grams: 30)], store: .bundled).count == 2)
        // A cup elsewhere in the photo.
        let apart = cup(grams: 22, box: NormalizedRect(x: 0.7, y: 0.1, width: 0.2, height: 0.3))
        #expect(ScanPipeline.countingContainersOnce([drink(packagingG: 20), apart], store: .bundled).count == 2)
    }

    @Test func aReusableBowlIsNotPackaging() {
        let fruit = IdentifiedComponent(name: "Cut fruit bowl", category: .food, boundingBox: drinkBox,
                                        identifiers: Identifiers(packagingMaterials: [share("ceramic", 100)]),
                                        quantities: Quantities(massKg: 0.25, packagingMassG: 40, foodGroup: "other_fruit"))
        let prepared = ScanPipeline.countingContainersOnce([fruit], store: .bundled)
        #expect(prepared[0].quantities.packagingMassG == nil)
        #expect(!FoodServing.isPackaged(prepared[0].makeComponent()))
    }

    @Test func itemsOfOneKindShareTheirPackaging() {
        let lead = IdentifiedComponent(name: "Dish soap", category: .household, boundingBox: .full,
                                       identifiers: Identifiers(materials: [share("detergent_formula", 100)],
                                                                packagingMaterials: [share("pet", 100)]),
                                       quantities: Quantities(massKg: 0.5, packagingMassG: 30))
        let other = IdentifiedComponent(name: "Dish soap", category: .household, boundingBox: .full)
        let prepared = ScanPipeline.withGenericKeys([lead, other])
        #expect(prepared[1].identifiers.packagingMaterials == [share("pet", 100)])
    }

    // MARK: Identify

    @Test func identifyReportsEachContainerOnceWithItsMaterials() throws {
        let system = ClaudeClient.identifySystemPrompt(vocabulary: ReferenceStore.bundled.vocabulary, carbonEstimateOnly: true)
        #expect(system.contains("Report each container once"))
        #expect(system.contains("packaging_materials"))
        #expect(system.contains("plastic straw 0.5-1 g"))
        #expect(system.contains("pet_thermoform"))
        #expect(!system.contains("food_organic"))
        let identifiers = ReportComponentsTool.carbonEstimateOnlySchema["properties"]?["components"]?["items"]?["properties"]?["identifiers"]
        #expect(identifiers?["properties"]?["packaging_materials"]?["type"] == "array")
        let required = identifiers?["required"]?.array?.compactMap(\.string) ?? []
        #expect(!required.contains("packaging_materials"), "optional, so unpackaged items spend no output on it")
        // Alternatives keep their own schema.
        #expect(SchemaParts.identifiers["properties"]?["packaging_materials"] == nil)

        let input: JSONValue = ["components": [[
            "name": "Thai iced tea", "category": "food", "bounding_box": ["x": 0, "y": 0, "width": 0.3, "height": 0.5],
            "identifiers": ["brand": .null, "model": .null, "gtin": .null, "materials": [],
                            "packaging_materials": [["material": "pet_thermoform", "percent": 95], ["material": "pp", "percent": 5],
                                                    ["material": "paper", "percent": 0]]],
            "quantities": ["mass_kg": 0.45, "packaging_mass_g": 21, "food_group": "milk_tea"],
        ], [
            "name": "Laptop", "category": "electronic", "bounding_box": ["x": 0.5, "y": 0.5, "width": 0.3, "height": 0.3],
            "identifiers": ["brand": .null, "model": .null, "gtin": .null, "materials": []],
        ]]]
        let response = try ReportComponentsTool.parse(input)
        #expect(response.components[0].identifiers.packagingMaterials == [share("pet_thermoform", 95), share("pp", 5)])
        #expect(response.components[1].identifiers.packagingMaterials == nil)
    }
}
