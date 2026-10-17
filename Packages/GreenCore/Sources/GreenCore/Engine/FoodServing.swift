/// One basis for food (spec §5.6): every food metric is per serving and a year is servings/week × 52, so
/// package-level values (a box's carbon, its packaging plastic) must be scaled down to one serving.
public enum FoodServing {
    /// Used when neither the item nor its record states a serving: 100 g, the nutrition-label reference
    /// amount, or the whole pack when it is smaller.
    public static let referenceKg = 0.1

    /// The drink equivalent: 12 fl oz (355 mL), the US label reference amount for beverages and one can.
    public static let drinkReferenceKg = 0.355

    /// Food groups that are drinks even when identify gives a mass instead of a volume.
    static let drinkGroups: Set<String> = ["bottled_water", "soft_drinks"]

    /// A drink is given as a volume or belongs to a drink food group.
    public static func isDrink(_ component: Component) -> Bool {
        component.quantities.volumeLiters != nil || component.quantities.foodGroup.map(drinkGroups.contains) == true
    }

    /// A packaged product has a barcode or stated packaging; an unpackaged portion (a plated burger) is
    /// itself one serving.
    public static func isPackaged(_ component: Component) -> Bool {
        !(component.identifiers.gtin?.isEmpty ?? true) || (component.quantities.packagingMassG ?? 0) > 0
    }

    /// The pack's mass: the identified unit mass, else the record's net quantity.
    public static func packageKg(_ component: Component, recordNetKg: Double? = nil) -> Double? {
        component.quantities.massKg ?? component.quantities.volumeLiters ?? recordNetKg
    }

    /// kg eaten per serving: the stated serving, else the record's, else the reference amount for a pack,
    /// else the portion's own mass.
    public static func servingKg(_ component: Component, recordServingKg: Double? = nil, recordNetKg: Double? = nil) -> Double? {
        if let stated = component.quantities.servingKg, stated > 0 { return stated }
        if let record = recordServingKg, record > 0 { return record }
        let pack = packageKg(component, recordNetKg: recordNetKg)
        if isPackaged(component) {
            let reference = isDrink(component) ? drinkReferenceKg : referenceKg
            return min(pack ?? reference, reference)
        }
        return pack
    }

    /// Grams of ground coffee in a brewed cup per gram of drink: ~15 g of grounds for a 250 mL cup.
    public static let brewedCoffeeGroundsShare = 0.06

    /// Share of a serving's mass that the food factor applies to. Coffee factors are per kg of beans, so a
    /// brewed drink (a cup, latte or espresso, or anything given as a volume) counts only its grounds; beans
    /// and everything else count in full.
    public static func dryIngredientShare(group: String, component: Component) -> Double {
        guard group == "coffee" else { return 1 }
        let name = component.name.lowercased()
        let brewedWords = ["cup", "latte", "espresso", "americano", "cappuccino", "mocha", "brew", "drink", "iced", "macchiato"]
        let isBrewed = component.quantities.volumeLiters != nil || brewedWords.contains { name.contains($0) }
        let isBeans = ["bean", "ground", "bag", "pod", "capsule"].contains { name.contains($0) }
        return isBrewed && !isBeans ? brewedCoffeeGroundsShare : 1
    }

    /// Fraction of one pack eaten per serving (0–1), for package-level values; 1 when the pack mass is unknown.
    public static func packageShare(servingKg: Double, packageKg: Double?) -> Double {
        guard let packageKg, packageKg > 0, servingKg > 0 else { return 1 }
        return min(servingKg / packageKg, 1)
    }
}
