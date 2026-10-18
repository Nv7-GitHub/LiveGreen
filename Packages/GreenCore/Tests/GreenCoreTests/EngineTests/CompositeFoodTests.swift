import Foundation
import Testing
@testable import GreenCore

@Suite("Composite, processed and cooked foods")
struct CompositeFoodTests {
    let store = ReferenceStore.bundled
    let resolver = FactorModelResolver(store: .bundled)

    func food(_ name: String, group: String?, kg: Double, cooked: Bool? = nil, packagingG: Double? = nil) -> Component {
        Component(name: name, category: .food,
                  quantities: Quantities(massKg: kg, servingKg: kg, packagingMassG: packagingG, foodGroup: group, cooked: cooked))
    }

    func carbon(_ component: Component) throws -> Double {
        try #require(resolver.food(component).metrics[.carbon]).value
    }

    func factor(_ group: String) throws -> FoodFactor {
        try #require(store.foodFactor(group: group))
    }

    @Test func mixedDrinksAreScoredAsServedNotAsMilk() throws {
        // A 0.5 kg bubble tea was 0.5 kg of milk (1.6 kg CO2e, 314 L); as a milk tea, ice and tea included, it is ~0.66.
        let boba = food("Brown sugar bubble tea", group: "milk_tea", kg: 0.5)
        #expect(abs(try carbon(boba) - 0.5 * factor("milk_tea").kgCO2ePerKg) < 1e-9)
        #expect((0.5...0.8).contains(try carbon(boba)))
        #expect(try #require(resolver.food(boba).metrics[.water]).value < 0.5 * factor("milk").litersPerKg / 2)
        for group in ["tea", "milk_tea", "latte", "smoothie", "juice", "yogurt", "ice_cream", "baked_goods", "candy",
                      "potato_crisps", "fries", "preserved_vegetables"] {
            #expect(store.foodFactor(group: group)?.group == group, "\(group) row")
        }
        #expect(FoodServing.isDrink(Component(name: "Thai tea", category: .food, quantities: Quantities(massKg: 0.45, foodGroup: "milk_tea"))))
    }

    @Test func aDrinkFiledUnderOneIngredientGetsItsCompositeRow() throws {
        #expect(FoodServing.factorKey(food("Iced latte", group: "coffee", kg: 0.45)) == "latte")
        #expect(FoodServing.factorKey(food("Strawberry smoothie", group: "milk", kg: 0.45)) == "smoothie")
        #expect(FoodServing.factorKey(food("Thai iced milk tea", group: "soft_drinks", kg: 0.45)) == "milk_tea")
        #expect(FoodServing.factorKey(food("Matcha latte", group: "milk", kg: 0.45)) == "milk_tea")
        #expect(FoodServing.factorKey(food("Thai tea frappé", group: "milk", kg: 0.5)) == "milk_tea")
        // The ingredient group stays when the name says nothing more, and a plant-milk drink keeps its group.
        #expect(FoodServing.factorKey(food("Black coffee", group: "coffee", kg: 0.35)) == "coffee")
        #expect(FoodServing.factorKey(food("Glass of milk", group: "milk", kg: 0.25)) == "milk")
        #expect(FoodServing.factorKey(food("Oat milk latte", group: "soy_milk", kg: 0.35)) == "soy_milk")
        // An iced latte was black coffee before (6% grounds, no milk): now milk and two shots.
        let latte = food("Iced latte", group: "coffee", kg: 0.45)
        #expect(abs(try carbon(latte) - 0.45 * factor("latte").kgCO2ePerKg) < 1e-9)
    }

    @Test func processedFoodsAreNotRawCommodities() throws {
        #expect(store.foodFactor(group: "chips")?.group == "potato_crisps")
        #expect(store.foodFactor(group: "French fries")?.group == "fries")
        #expect(store.foodFactor(group: "potato")?.group == "potatoes")
        #expect(store.foodFactor(group: "Bolthouse Farms carrot juice")?.group == "juice")
        #expect(store.foodFactor(group: "Marinated artichoke hearts")?.group == "preserved_vegetables")
        #expect(store.foodFactor(group: "Chocolate chip cookie")?.group == "baked_goods")
        #expect(store.foodFactor(group: "Thai iced milk tea")?.group == "milk_tea")
        #expect(store.foodFactor(group: "oat milk")?.group == "soy_milk")
        // A 28 g serving of crisps was 0.013 kg CO2e at the raw-potato factor; Walkers' label gives ~0.06.
        let crisps = food("Potato chips", group: "potato_crisps", kg: 0.028)
        #expect(abs(try carbon(crisps) - 0.028 * 2.2) < 1e-9)
        #expect(try factor("juice").kgCO2ePerKg > 1.8 * factor("root_vegetables").kgCO2ePerKg)
    }

    @Test func cookedPortionsCountTheirDryWeight() throws {
        let rice = try factor("rice").kgCO2ePerKg
        // A plated portion of rice is cooked unless identify says it is dry.
        #expect(abs(try carbon(food("White rice", group: "rice", kg: 0.15)) - 0.15 / 2.7 * rice) < 1e-9)
        #expect(abs(try carbon(food("Rice", group: "rice", kg: 0.15, cooked: false)) - 0.15 * rice) < 1e-9)
        // A bag of rice is the dry product.
        #expect(abs(try carbon(food("Rice bag", group: "rice", kg: 0.1, packagingG: 30)) - 0.1 * rice) < 1e-9)
        // Pasta and canned chickpeas only when identify says cooked; bread never is.
        let wheat = try factor("wheat_rye").kgCO2ePerKg
        #expect(abs(try carbon(food("Spaghetti", group: "wheat_rye", kg: 0.2, cooked: true)) - 0.2 / 2.3 * wheat) < 1e-9)
        #expect(abs(try carbon(food("Bread roll", group: "wheat_rye", kg: 0.06)) - 0.06 * wheat) < 1e-9)
        let pulses = try factor("other_pulses").kgCO2ePerKg
        #expect(abs(try carbon(food("Canned chickpeas", group: "other_pulses", kg: 0.1, cooked: true, packagingG: 40))
            - 0.1 / 2.5 * pulses) < 1e-9)
        #expect(abs(try carbon(food("Porridge", group: "oatmeal", kg: 0.25, cooked: true))
            - 0.25 / 5 * factor("oatmeal").kgCO2ePerKg) < 1e-9)
        #expect(FoodServing.cookedDivisor(group: "beef", component: food("Steak", group: "beef", kg: 0.2, cooked: true)) == 1)
    }

    @Test func aSwapOfTheSameFoodIsAsCookedAsTheOriginal() {
        let original = food("Spaghetti", group: "wheat_rye", kg: 0.2, cooked: true)
        let wholeWheat = Alternative(name: "Whole-wheat spaghetti", category: .food,
                                     quantities: Quantities(servingKg: 0.2, foodGroup: "wheat_rye"), rationale: "")
        #expect(wholeWheat.onBasis(of: original).quantities.cooked == true)
        // Another food group decides for itself.
        let lentils = Alternative(name: "Lentil salad", category: .food, quantities: Quantities(servingKg: 0.2, foodGroup: "other_pulses"),
                                  rationale: "")
        #expect(lentils.onBasis(of: original).quantities.cooked == nil)
    }

    @Test func identifyAsksForFoodsAsServed() throws {
        let system = ClaudeClient.identifySystemPrompt(vocabulary: ReferenceStore.bundled.vocabulary, carbonEstimateOnly: true)
        #expect(system.contains("milk_tea for tea with milk"))
        #expect(system.contains("soft_drinks only for sodas"))
        #expect(system.contains("potato_crisps"))
        #expect(system.contains("cooked: true for a portion cooked from a dry grain"))
        let quantities = ReportComponentsTool.carbonEstimateOnlySchema["properties"]?["components"]?["items"]?["properties"]?["quantities"]
        #expect(quantities?["properties"]?["cooked"]?["type"] == ["boolean", "null"])

        let input: JSONValue = ["components": [[
            "name": "Steamed rice", "category": "food", "bounding_box": ["x": 0, "y": 0, "width": 0.3, "height": 0.3],
            "identifiers": ["brand": .null, "model": .null, "gtin": .null, "materials": []],
            "quantities": ["mass_kg": 0.18, "serving_kg": 0.18, "food_group": "rice", "cooked": true],
        ]]]
        #expect(try ReportComponentsTool.parse(input).components[0].quantities.cooked == true)
    }
}
