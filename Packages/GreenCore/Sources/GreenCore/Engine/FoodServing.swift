/// What one unit of a food item's metrics covers (spec §5.6), and so what its usage counts per week.
public enum FoodBasis: Sendable, Hashable {
    /// One serving of `kg` (nil when unknown); a year is servings/week × 52. Photographed meals, plated portions,
    /// unpackaged produce, and packs whose size is not on record.
    case serving(kg: Double?)
    /// One whole pack of `kg` net, from the record of a scanned barcode; a year is packs/week × 52.
    case pack(kg: Double)
}

/// The two bases for food (spec §5.6). A pack whose barcode record states its net quantity is scored as the whole
/// pack (`Quantities.packNetKg`): carbon, water and land for its full contents and all of its packaging plastic.
/// Everything else is per serving and a year is servings/week × 52, so package-level values (a box's carbon, its
/// packaging plastic) are scaled down to one serving.
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

    /// A packaged product has a barcode, a pack size on record or stated packaging; an unpackaged portion (a
    /// plated burger) is itself one serving.
    public static func isPackaged(_ component: Component) -> Bool {
        !(component.identifiers.gtin?.isEmpty ?? true) || component.quantities.packNetKg != nil
            || (component.quantities.packagingMassG ?? 0) > 0
    }

    /// The pack's mass: the net quantity on record for a per-pack item, else the identified unit mass, else the
    /// record's net quantity.
    public static func packageKg(_ component: Component, recordNetKg: Double? = nil) -> Double? {
        component.quantities.packNetKg ?? component.quantities.massKg ?? component.quantities.volumeLiters ?? recordNetKg
    }

    /// The food's basis; nil for other categories.
    public static func basis(of component: Component) -> FoodBasis? {
        guard component.category == .food else { return nil }
        if let pack = component.quantities.packNetKg, pack > 0 { return .pack(kg: pack) }
        return .serving(kg: servingKg(component))
    }

    /// Whether the item's metrics are for one whole pack.
    public static func isPerPack(_ component: Component) -> Bool {
        if case .pack = basis(of: component) { return true }
        return false
    }

    /// kg of food one unit of the item's metrics covers: the whole pack for a per-pack item, else one serving.
    public static func unitKg(_ component: Component, recordServingKg: Double? = nil, recordNetKg: Double? = nil) -> Double? {
        if case .pack(let kg) = basis(of: component) { return kg }
        return servingKg(component, recordServingKg: recordServingKg, recordNetKg: recordNetKg)
    }

    /// Servings in one pack of a per-pack item (at least 1), else 1. Turns per-serving figures (identify's
    /// estimates, servings a week) into per-pack ones.
    public static func servingsPerPack(_ component: Component) -> Double {
        guard case .pack(let pack) = basis(of: component), let serving = servingKg(component), serving > 0 else { return 1 }
        return max(pack / serving, 1)
    }

    /// Amounts that grow with the mass of food: they scale between a serving and a pack. Shares, ratings and
    /// decomposition time do not, and neither does plastic: the AI gives it for the whole package pictured
    /// (`PromptParts.basis`), which for a per-pack item is already the pack's.
    public static let massScaledMetrics: Set<MetricKey> = [.carbon, .water, .land, .waterPollution]

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

    /// Fraction of one pack eaten per serving (0–1), for package-level values; 1 when the pack mass is unknown or
    /// the unit is the whole pack.
    public static func packageShare(servingKg: Double, packageKg: Double?) -> Double {
        guard let packageKg, packageKg > 0, servingKg > 0 else { return 1 }
        return min(servingKg / packageKg, 1)
    }
}

extension FoodServing {
    /// Servings a week when nothing says how often the food is eaten.
    public static let defaultServingsPerWeek = 1.0

    /// Packs a week for a per-pack item from servings a week: servings × serving ÷ pack.
    public static func packsPerWeek(servingsPerWeek: Double, for component: Component) -> Double {
        servingsPerWeek / servingsPerPack(component)
    }

    /// Packs a week of a per-pack item: the stated packs, else its servings a week (or the default) in packs, so an
    /// unstated rate counts the same food a year as the per-serving default did rather than a whole pack a week.
    public static func packsPerWeek(of component: Component) -> Double {
        component.usage?.packsPerWeek
            ?? packsPerWeek(servingsPerWeek: component.usage?.servingsPerWeek ?? defaultServingsPerWeek, for: component)
    }

    /// The item as one serving, the way identify and the swap suggesters see food: a per-pack item's amounts are
    /// divided by the servings in its pack (its plastic stays the package's), its pack size becomes the item's mass
    /// and its packs a week are given as servings. Other items are returned unchanged.
    public static func servingView(of component: Component) -> Component {
        guard isPerPack(component) else { return component }
        let servings = servingsPerPack(component)
        var view = component
        view.quantities.servingKg = servingKg(component)
        view.quantities.massKg = component.quantities.massKg ?? component.quantities.packNetKg
        view.quantities.packNetKg = nil
        for metric in massScaledMetrics {
            view.metrics[metric] = component.metrics[metric]?.scaled(by: 1 / servings)
        }
        var usage = component.usage ?? UsageProfile()
        usage.servingsPerWeek = packsPerWeek(of: component) * servings
        usage.packsPerWeek = nil
        view.usage = usage
        return view
    }
}

extension Alternative {
    /// The swap on the same basis as the item it replaces. A food swap for a per-pack item covers the same amount of
    /// food, bought as often: one pack of the original's net quantity at its packs a week, so the two are compared
    /// per kg eaten whatever the swap's own pack size. Its estimates are per serving of the original (the suggesters
    /// see `FoodServing.servingView`), so without a serving of its own it takes the original's; its packaging, given
    /// for its own pack, is scaled to the original's pack size as Open Food Facts records are. Other swaps are
    /// returned unchanged.
    public func onBasis(of original: Component) -> Alternative {
        guard kind == .product, category == .food, case .pack(let kg) = FoodServing.basis(of: original) else { return self }
        var copy = self
        if (copy.quantities.servingKg ?? 0) <= 0 { copy.quantities.servingKg = FoodServing.servingKg(original) }
        if let ownPack = quantities.packNetKg ?? quantities.massKg ?? quantities.volumeLiters, ownPack > 0 {
            let share = kg / ownPack
            copy.quantities.packagingMassG = quantities.packagingMassG.map { $0 * share }
            copy.fallbackEstimates[.plasticMass] = fallbackEstimates[.plasticMass].map {
                EstimateRange(value: $0.value * share, low: $0.low * share, high: $0.high * share)
            }
        }
        copy.quantities.packNetKg = kg
        copy.usage = original.usage
        return copy
    }
}
