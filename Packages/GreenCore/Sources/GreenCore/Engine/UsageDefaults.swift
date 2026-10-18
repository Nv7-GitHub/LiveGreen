import Foundation

/// How often a consumable is had in a typical week, used for its per-year figures until the user says (spec §5.6).
/// Identify used to guess this per scan, and its guesses changed from run to run (1 or 2 drinks a week for one photo,
/// 2 or 3 parfaits), so per-year totals of the same photo differed by up to 14×. The rates here are fixed per food
/// group and kind of item, so a rescan gives the same year.
///
/// They are LiveGreen's assumptions, not measurements: round rates for someone who has the item regularly, grouped
/// as daily drinks, everyday foods, mains and treats, and occasional foods. Every per-year figure shows the rate it
/// uses ("3 servings a week") and the item's usage card edits it. An answer replaces it and is remembered for that
/// kind of item (`kindKey`), so later scans of it start from the user's own rate.
public enum UsageDefaults {
    /// Servings a week by food group (the canonical groups of `food_factors.json`).
    static let servingsByGroup: [String: Double] = [
        // Plain drinks most people have most days.
        "coffee": 5, "tea": 5, "milk": 5, "soy_milk": 5, "bottled_water": 5,
        // Everyday foods and café drinks: a few times a week.
        "latte": 3, "juice": 3, "soft_drinks": 3, "wheat_rye": 3, "rice": 3, "oatmeal": 3, "maize": 3, "potatoes": 3,
        "eggs": 3, "cheese": 3, "yogurt": 3, "apples": 3, "bananas": 3, "citrus": 3, "berries_grapes": 3,
        "other_fruit": 3, "tomatoes": 3, "brassicas": 3, "onions_leeks": 3, "root_vegetables": 3,
        "other_vegetables": 3, "nuts": 3, "groundnuts": 3,
        // Mains, treats and drinks with sugar or alcohol: twice a week.
        "beef": 2, "beef_dairy_herd": 2, "pork": 2, "poultry": 2, "fish_farmed": 2, "tofu": 2, "other_pulses": 2,
        "peas": 2, "milk_tea": 2, "smoothie": 2, "wine": 2, "barley": 2, "baked_goods": 2, "candy": 2,
        "dark_chocolate": 2, "potato_crisps": 2,
        // Occasional foods: once a week.
        "lamb": 1, "prawns_farmed": 1, "ice_cream": 1, "fries": 1, "preserved_vegetables": 1,
    ]

    /// Servings a week of a food whose group is not in the table.
    public static let otherFoodServingsPerWeek = 2.0

    /// Uses a week of packaging that held a drink (cups, lids, straws, bottles, cans), as often as a café drink.
    static let drinkContainerUsesPerWeek = 3.0
    static let drinkContainerWords = ["cup", "lid", "straw", "bottle", "can", "sleeve"]

    /// Uses a week of other packaging (wrappers, bags, boxes, trays) and of personal-care items: twice and once.
    public static let packagingUsesPerWeek = 2.0
    public static let personalCareUsesPerWeek = 1.0

    /// The typical rate for a consumable: servings a week for food, uses a week for packaging and personal care; nil
    /// for durables, which are annualized over their lifespan instead.
    public static func typicalPerWeek(for component: Component, reference: any ReferenceProviding) -> Double? {
        switch component.category {
        case .food:
            return foodGroup(of: component, reference: reference).flatMap { servingsByGroup[$0] } ?? otherFoodServingsPerWeek
        case .packaging:
            let words = Set(ReferenceKey.normalize(component.name).split(separator: "_").map { Identifiers.singular(String($0)) })
            return drinkContainerWords.contains(where: words.contains) ? drinkContainerUsesPerWeek : packagingUsesPerWeek
        case .personalCare:
            return personalCareUsesPerWeek
        case .electronic, .clothing, .household:
            return nil
        }
    }

    /// What an answer is remembered under: the food group for food ("food:latte"), so every latte reads alike, and the
    /// item's kind (barcode, brand and model, or generic kind) for packaging and personal care. Nil for durables and
    /// for packaging that follows its food (`Component.parentID`).
    public static func kindKey(for component: Component, reference: any ReferenceProviding) -> String? {
        switch component.category {
        case .food:
            let group = foodGroup(of: component, reference: reference) ?? ReferenceKey.normalize(component.name)
            return group.isEmpty ? nil : "food:\(group)"
        case .packaging, .personalCare:
            guard component.parentID == nil, let key = component.resolutionKey else { return nil }
            return "\(component.category.rawValue):\(key)"
        case .electronic, .clothing, .household:
            return nil
        }
    }

    /// The item's rate in the unit `kindKey` remembers: servings a week for food (a per-pack item's packs converted, so
    /// a later scan of the same food per serving reads alike), uses a week otherwise. Nil without a stated rate.
    public static func perWeek(of component: Component) -> Double? {
        guard let usage = component.usage else { return nil }
        switch component.category {
        case .food where FoodServing.isPerPack(component):
            return FoodServing.packsPerWeek(of: component) * FoodServing.servingsPerPack(component)
        case .food:
            return usage.servingsPerWeek
        case .packaging, .personalCare:
            return usage.usesPerWeek
        case .electronic, .clothing, .household:
            return nil
        }
    }

    /// The component with `perWeek` as its rate: servings for food (a per-pack item counts its packs from them),
    /// uses otherwise. Other usage fields are kept.
    public static func setting(_ perWeek: Double, source: UsageSource, on component: Component) -> Component {
        var result = component
        var usage = component.usage ?? UsageProfile()
        switch component.category {
        case .food:
            usage.servingsPerWeek = perWeek
            usage.packsPerWeek = nil
        case .packaging, .personalCare:
            usage.usesPerWeek = perWeek
        case .electronic, .clothing, .household:
            return component
        }
        usage.source = source
        result.usage = usage
        return result
    }

    /// The canonical food group the factor model scores the item with (`FoodServing.factorKey`), when it has one.
    static func foodGroup(of component: Component, reference: any ReferenceProviding) -> String? {
        reference.foodFactor(group: FoodServing.factorKey(component))?.group
    }
}
