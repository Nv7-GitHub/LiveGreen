import Foundation

/// The local question catalogue for T4 items and for T3 foods of an uncertain group (see `SpecQuestion`). Questions
/// ask only what a shopper can tell at a glance (what it is mostly made of, how big it is, what kind of food or device
/// it is) and every option maps to keys that exist in the bundled reference tables. When one answer needs a second
/// missing quantity (a material question for a garment with no mass), the option fills it with a typical value for
/// that kind of item. Single-material questions are never asked about things one material cannot describe.
public enum SpecQuestionCatalog {
    /// Candidate questions for one T4 component, most useful first. The pipeline keeps the first candidate whose
    /// options actually resolve through the factor model, and drops options that do not. Nothing is asked about items
    /// that are only partly in the picture or in the background: they are rarely the user's, and their details
    /// cannot be told from the photo.
    public static func candidates(for component: Component, store: ReferenceStore) -> [SpecQuestion] {
        guard !isIncidental(component) else { return [] }
        return switch component.category {
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

    /// Questions for a food already on the factor model (T3) whose group the AI picks inconsistently between runs and
    /// where the pick moves the numbers several-fold: dairy or plant milk (a chia pudding came back as milk, soy milk
    /// or pulses, land 2.8× apart), and the main protein (beef is ~30× tofu). Asked only when the name does not
    /// already say which, so a "Beef burger" or "Oat milk" goes straight through.
    public static func variants(for component: Component, store: ReferenceStore) -> [SpecQuestion] {
        guard component.category == .food, !isIncidental(component),
              let group = store.foodFactor(group: FoodServing.factorKey(component))?.group else { return [] }
        let name = component.name
        if milkGroups.contains(group) || matches(name, milkDishWords) {
            guard !matches(name, dairyWords + plantMilkWords) else { return [] }
            let dairy = group == "yogurt" ? ("Dairy yogurt", "yogurt") : ("Dairy milk", "milk")
            let kinds = [dairy, ("Plant-based (soy, oat, almond)", "soy_milk")]
            return [question(component, .foodType, "Is it made with dairy or plant milk?",
                             kinds.map { SpecOption(label: $0.0, foodGroup: $0.1) })]
        }
        if proteinGroups.contains(group) {
            guard !matches(name, proteinWords) else { return [] }
            let kinds: [(String, String)] = [("Beef or lamb", "beef"), ("Pork", "pork"), ("Chicken or turkey", "poultry"),
                                             ("Fish or seafood", "fish_farmed"), ("Tofu or beans", "tofu")]
            return [question(component, .foodType, "What is the main protein?",
                             kinds.map { SpecOption(label: $0.0, foodGroup: $0.1) })]
        }
        return []
    }

    static let milkGroups: Set<String> = ["milk", "soy_milk", "yogurt"]
    /// Dishes that are mostly milk whatever group the AI gave them.
    static let milkDishWords = ["pudding", "chia", "overnight"]
    static let dairyWords = ["dairy", "cow", "cows", "whole", "skim", "skimmed", "greek", "buttermilk", "kefir"]
    static let plantMilkWords = ["oat", "oatmilk", "soy", "soya", "soymilk", "almond", "coconut", "cashew", "rice",
                                 "plant", "plant-based", "vegan", "dairy-free"]
    static let proteinGroups: Set<String> = ["beef", "beef_dairy_herd", "lamb", "pork", "poultry", "fish_farmed",
                                             "prawns_farmed", "tofu"]
    static let proteinWords = [
        "beef", "steak", "veal", "brisket", "lamb", "mutton", "pork", "bacon", "ham", "sausage", "chorizo", "salami",
        "chicken", "turkey", "duck", "fish", "salmon", "tuna", "cod", "tilapia", "shrimp", "prawn", "crab", "lobster",
        "sushi", "tofu", "tempeh", "seitan", "vegan", "vegetarian", "veggie", "plant-based", "bean", "lentil",
        "falafel", "chickpea",
    ]

    // MARK: Clothing

    static func clothing(_ component: Component, store: ReferenceStore) -> [SpecQuestion] {
        // The garment model is a textile's: eyewear, helmets, jewellery and shoes (rubber soles) would become cloth,
        // and "Light, like a T-shirt" is no size for a pair of glasses.
        guard isTextile(component, store: store) else { return [] }
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
        if !knowsMaterial, !isComposite(component) {
            let mass = knowsMass ? nil : typicalHouseholdKg(component.name)
            // Glass or ceramic household goods are tableware (mugs, bowls, vases), not bottles and jars.
            let materials: [(String, String)] = [("Wood", "wood"), ("Plastic", "other_plastic"), ("Metal", "steel"),
                                                 ("Glass or ceramic", "ceramic"), ("Fabric", "cotton_textile")]
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

    // MARK: What can be asked

    /// Words in a name that say the item is only partly in the picture or far behind the subject.
    static let incidentalWords = ["background", "partial", "partially", "distant", "cropped"]

    /// Partly visible or background items ("White electric SUV (background)").
    static func isIncidental(_ component: Component) -> Bool {
        matches(component.name, incidentalWords)
    }

    /// Over this mass an item is an assembly (a car, a piano, a hot tub), never one material.
    static let compositeMassKg = 100.0
    /// Over this AI estimate (kg CO2e) an item is a complex product, never one material.
    static let compositeCarbonKg = 1000.0
    /// A material with at least this share (%) is a major one; two make the item multi-material.
    static let majorMaterialPercent = 15.0

    /// Things no single material describes: two or more major materials in identify's split, a mass over 100 kg or an
    /// estimate over 1 t CO2e. "What is it mostly made of?" would turn them into a block of the answer: a "wood"
    /// electric SUV read 855 kg instead of ≈9 t.
    static func isComposite(_ component: Component) -> Bool {
        let major = Set(component.identifiers.materials.filter { $0.percent >= majorMaterialPercent }.map(\.material))
        if major.count >= 2 { return true }
        if (component.quantities.massKg ?? 0) > compositeMassKg { return true }
        let estimate = component.fallbackEstimates[.carbon]?.value ?? component.metrics[.carbon]?.value ?? 0
        return estimate > compositeCarbonKg
    }

    /// Worn things that are not textiles, or mostly not: eyewear, helmets, watches, jewellery and footwear (soles).
    static let nonTextileWords = [
        "glasses", "eyeglasses", "sunglasses", "spectacles", "goggles", "eyewear", "helmet", "watch", "watches",
        "smartwatch", "ring", "necklace", "bracelet", "earring", "jewelry", "jewellery", "umbrella", "shoe", "sneaker",
        "trainer", "boot", "sandal", "slipper", "heel", "loafer", "clog", "flip-flop", "skate", "cleat",
    ]

    /// Whether a garment's fiber describes it: not a non-textile kind, and not mostly a non-fiber material
    /// (acetate frames, a plastic visor) in identify's split.
    static func isTextile(_ component: Component, store: ReferenceStore) -> Bool {
        guard !matches(component.name, nonTextileWords) else { return false }
        let nonFiber = component.identifiers.materials.filter { store.fiberFactor(material: $0.material) == nil }
        return nonFiber.reduce(0) { $0 + $1.percent } < 50
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
