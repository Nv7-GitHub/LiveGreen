import Foundation

/// The local question catalogue for T4 items (see `SpecQuestion`). Questions ask only what a shopper can tell at a
/// glance (what it is mostly made of, how big it is, what kind of food or device it is) and every option maps to
/// keys that exist in the bundled reference tables. When one answer needs a second missing quantity (a material
/// question for a garment with no mass), the option fills it with a typical value for that kind of item.
public enum SpecQuestionCatalog {
    /// Candidate questions for one component, most useful first. The pipeline keeps the first candidate whose
    /// options actually resolve through the factor model, and drops options that do not.
    public static func candidates(for component: Component, store: ReferenceStore) -> [SpecQuestion] {
        switch component.category {
        case .food: food(component, store: store)
        case .clothing: clothing(component, store: store)
        case .household: household(component, store: store)
        case .packaging: packaging(component, store: store)
        case .electronic: electronic(component, store: store)
        // The factor model only covers a personal-care item's container, never its carbon.
        case .personalCare: []
        }
    }

    // MARK: Food

    static let regularPortionKg = 0.25

    static func food(_ component: Component, store: ReferenceStore) -> [SpecQuestion] {
        let q = component.quantities
        let knowsGroup = store.foodFactor(group: q.foodGroup ?? component.name) != nil
        let isDrink = FoodServing.isDrink(component) || matches(component.name, drinkWords)
        let knowsServing = FoodServing.servingKg(component).map { $0 > 0 } ?? false
        var questions: [SpecQuestion] = []
        if !knowsGroup {
            // A drink given as a volume counts as brewed (coffee) and as one drink-sized serving.
            let volume = isDrink && q.volumeLiters == nil ? FoodServing.drinkReferenceKg : nil
            let serving = !isDrink && !knowsServing ? regularPortionKg : nil
            let kinds: [(String, String)] = isDrink
                ? [("Soda or juice", "soft_drinks"), ("Coffee", "coffee"), ("Milk", "milk"),
                   ("Beer or wine", "wine"), ("Water", "bottled_water")]
                : [("Beef or lamb", "beef"), ("Chicken, pork or fish", "poultry"), ("Cheese or dairy", "cheese"),
                   ("Bread, rice or pasta", "wheat_rye"), ("Veggies, fruit or beans", "other_vegetables")]
            questions.append(question(component, .foodType,
                                      isDrink ? "What kind of drink is it?" : "What is it mostly made of?",
                                      kinds.map { SpecOption(label: $0.0, servingKg: serving, volumeLiters: volume, foodGroup: $0.1) }))
        }
        if !knowsServing {
            let sizes: [(String, Double)] = isDrink
                ? [("Small cup", 0.25), ("Can or bottle", 0.355), ("Large", 0.6)]
                : [("Snack", 0.1), ("Regular plate", regularPortionKg), ("Big plate", 0.45)]
            questions.append(question(component, .portion, "How big is the portion?",
                                      sizes.map { SpecOption(label: $0.0, servingKg: $0.1) }))
        }
        return questions
    }

    // MARK: Clothing

    static func clothing(_ component: Component, store: ReferenceStore) -> [SpecQuestion] {
        let knowsFiber = component.identifiers.materials.contains { $0.percent > 0 && store.fiberFactor(material: $0.material) != nil }
        let knowsMass = (component.quantities.massKg ?? 0) > 0
        var questions: [SpecQuestion] = []
        if !knowsFiber {
            let mass = knowsMass ? nil : typicalGarmentKg(component.name)
            let fibers: [(String, String)] = [("Cotton or denim", "cotton"), ("Polyester or nylon", "polyester"),
                                              ("Wool", "wool"), ("Leather", "leather")]
            questions.append(question(component, .material, "What is it mainly made of?",
                                      fibers.map { SpecOption(label: $0.0, materials: [MaterialShare(material: $0.1, percent: 100)], massKg: mass) }))
        }
        if !knowsMass {
            let sizes: [(String, Double)] = [("Light, like a T-shirt", 0.2), ("Medium, like jeans", 0.6),
                                             ("Heavy, like a coat or boots", 1.2)]
            questions.append(question(component, .size, "How heavy is it?", sizes.map { SpecOption(label: $0.0, massKg: $0.1) }))
        }
        return questions
    }

    /// Typical garment masses (kg), for when only the fiber is asked.
    static func typicalGarmentKg(_ name: String) -> Double {
        let table: [([String], Double)] = [
            (["sock", "underwear", "brief", "bra"], 0.05),
            (["hat", "cap", "beanie", "scarf", "glove", "tie"], 0.12),
            (["t-shirt", "tshirt", "tee", "top", "blouse", "tank"], 0.2),
            (["shirt", "dress", "skirt", "shorts", "leggings"], 0.3),
            (["sweater", "hoodie", "jumper", "sweatshirt", "cardigan", "fleece"], 0.5),
            (["jeans", "pants", "trousers", "chinos"], 0.6),
            (["shoe", "sneaker", "trainer", "boot", "sandal", "bag", "backpack", "purse"], 0.8),
            (["jacket", "coat", "parka", "blazer", "suit"], 1.0),
        ]
        return typicalValue(name, table) ?? 0.4
    }

    // MARK: Household

    static func household(_ component: Component, store: ReferenceStore) -> [SpecQuestion] {
        let knowsMaterial = MaterialBlend(materials: component.identifiers.materials, massG: 1, store: store) != nil
        let knowsMass = (component.quantities.massKg ?? 0) > 0
        var questions: [SpecQuestion] = []
        if !knowsMaterial {
            let mass = knowsMass ? nil : typicalHouseholdKg(component.name)
            let materials: [(String, String)] = [("Wood", "wood"), ("Plastic", "other_plastic"), ("Metal", "steel"),
                                                 ("Glass or ceramic", "glass"), ("Fabric", "cotton_textile")]
            questions.append(question(component, .material, "What is it mostly made of?",
                                      materials.map { SpecOption(label: $0.0, materials: [MaterialShare(material: $0.1, percent: 100)], massKg: mass) }))
        }
        if !knowsMass {
            let sizes: [(String, Double)] = [("Small, fits in a hand", 0.5), ("Medium, carry with both hands", 5),
                                             ("Large, like furniture", 30)]
            questions.append(question(component, .size, "How big is it?", sizes.map { SpecOption(label: $0.0, massKg: $0.1) }))
        }
        return questions
    }

    /// Typical masses (kg) of unpowered household goods, for when only the material is asked.
    static func typicalHouseholdKg(_ name: String) -> Double {
        let table: [([String], Double)] = [
            (["mug", "cup", "glass", "bottle", "vase"], 0.35),
            (["plate", "bowl", "towel", "pillow", "cushion"], 0.6),
            (["pan", "pot", "skillet", "blanket", "lamp", "basket", "bin"], 1.5),
            (["chair", "stool", "rug", "mirror"], 6),
            (["table", "desk", "dresser", "cabinet", "shelf", "bookcase"], 25),
            (["sofa", "couch", "bed", "mattress", "wardrobe"], 40),
        ]
        return typicalValue(name, table) ?? 2
    }

    // MARK: Packaging

    static func packaging(_ component: Component, store: ReferenceStore) -> [SpecQuestion] {
        let q = component.quantities
        let knowsMaterial = MaterialBlend(materials: component.identifiers.materials, massG: 1, store: store) != nil
        let knowsMass = (q.packagingMassG ?? q.massKg.map { $0 * 1000 } ?? 0) > 0
        var questions: [SpecQuestion] = []
        if !knowsMaterial {
            let mass = knowsMass ? nil : typicalPackagingG(component.name)
            let materials: [(String, String)] = [("Plastic", "other_plastic"), ("Paper or cardboard", "paperboard"),
                                                 ("Foam", "eps_foam"), ("Glass", "glass"), ("Metal", "aluminium")]
            questions.append(question(component, .material, "What is it made of?",
                                      materials.map { SpecOption(label: $0.0, materials: [MaterialShare(material: $0.1, percent: 100)], packagingMassG: mass) }))
        }
        if !knowsMass {
            let sizes: [(String, Double)] = [("Small, like a cup or wrapper", 10), ("Medium, like a bottle or box", 40),
                                             ("Large, like a big box or jug", 200)]
            questions.append(question(component, .size, "How big is it?", sizes.map { SpecOption(label: $0.0, packagingMassG: $0.1) }))
        }
        return questions
    }

    /// Typical packaging masses (g), for when only the material is asked.
    static func typicalPackagingG(_ name: String) -> Double {
        let table: [([String], Double)] = [
            (["wrapper", "bag", "pouch", "film", "lid", "straw"], 5),
            (["cup", "can", "sachet"], 13),
            (["bottle", "tray", "clamshell", "container", "takeout", "box"], 30),
            (["jar", "jug", "carton"], 150),
        ]
        return typicalValue(name, table) ?? 30
    }

    // MARK: Electronics

    /// An electronic is a T4 estimate only when its device type is missing from the table, so the question is what
    /// it is closest to; each option is a representative device of that kind.
    static func electronic(_ component: Component, store: ReferenceStore) -> [SpecQuestion] {
        guard store.deviceProfile(deviceType: component.quantities.deviceType ?? component.name) == nil else { return [] }
        let kinds: [(String, String)] = [("Small gadget", "smart_speaker"), ("Computer or screen", "monitor"),
                                         ("Kitchen appliance", "coffee_maker"), ("Big home appliance", "refrigerator")]
        return [question(component, .deviceKind, "What kind of device is it closest to?",
                         kinds.map { SpecOption(label: $0.0, deviceType: $0.1) })]
    }

    // MARK: Helpers

    static let drinkWords = ["drink", "juice", "soda", "smoothie", "shake", "latte", "coffee", "tea", "beer", "wine",
                             "milk", "lemonade", "kombucha", "cola"]

    private static func question(_ component: Component, _ topic: SpecQuestion.Topic, _ text: String,
                                 _ options: [SpecOption]) -> SpecQuestion {
        SpecQuestion(componentID: component.id, componentName: component.name, topic: topic, question: text, options: options)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && $0 != "-" }.map(String.init)
    }

    private static func matches(_ name: String, _ keywords: [String]) -> Bool {
        let tokens = words(name)
        return keywords.contains { keyword in tokens.contains { $0 == keyword || $0 == keyword + "s" } }
    }

    private static func typicalValue(_ name: String, _ table: [([String], Double)]) -> Double? {
        table.first { matches(name, $0.0) }?.1
    }
}
