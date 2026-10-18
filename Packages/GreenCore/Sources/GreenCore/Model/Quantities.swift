/// Physical quantities inferred during identification (spec §5.3), used by the factor model.
public struct Quantities: Codable, Sendable, Hashable {
    /// Item mass in kg.
    public var massKg: Double?
    /// Serving size in kg (food).
    public var servingKg: Double?
    /// Packaging mass in g.
    public var packagingMassG: Double?
    /// Screen diagonal in inches (displays).
    public var screenSizeInches: Double?
    /// Rated or label wattage.
    public var ratedPowerW: Double?
    /// Volume in liters (drinks, appliances).
    public var volumeLiters: Double?
    /// Reference-table key for food items, e.g. "beef", "coffee".
    public var foodGroup: String?
    /// Reference-table key for devices, e.g. "laptop", "monitor", "ebike_charger".
    public var deviceType: String?
    /// Net quantity of the whole pack in kg, from the product record of a scanned barcode. Set only when the
    /// record states it; the food's metrics are then for the whole pack instead of one serving (`FoodServing.basis`).
    /// Nil in scans saved by older builds, which stay per serving.
    public var packNetKg: Double?
    /// Food: true when the portion was cooked from a dry grain, pasta or pulse, so its mass includes absorbed water
    /// (`FoodServing.cookedYield`); false for the dry product; nil when identify did not say.
    public var cooked: Bool?
    /// Vehicles: what drives it. Nil when identify could not tell; the vehicle model then assumes petrol.
    public var powertrain: Powertrain?
    /// Household: true for goods that are used up and replaced (a cleaner, a paper notebook, a sponge), so a year
    /// counts how many are used (`usesPerContainer`) instead of dividing one item by a lifespan.
    public var consumable: Bool?
    /// Consumables: how many uses one item lasts (sprays or washes in a bottle, sessions in a notebook).
    public var usesPerContainer: Double?

    public init(massKg: Double? = nil, servingKg: Double? = nil, packagingMassG: Double? = nil,
                screenSizeInches: Double? = nil, ratedPowerW: Double? = nil, volumeLiters: Double? = nil,
                foodGroup: String? = nil, deviceType: String? = nil, packNetKg: Double? = nil, cooked: Bool? = nil,
                powertrain: Powertrain? = nil, consumable: Bool? = nil, usesPerContainer: Double? = nil) {
        self.massKg = massKg
        self.servingKg = servingKg
        self.packagingMassG = packagingMassG
        self.screenSizeInches = screenSizeInches
        self.ratedPowerW = ratedPowerW
        self.volumeLiters = volumeLiters
        self.foodGroup = foodGroup
        self.deviceType = deviceType
        self.packNetKg = packNetKg
        self.cooked = cooked
        self.powertrain = powertrain
        self.consumable = consumable
        self.usesPerContainer = usesPerContainer
    }
}

extension Quantities {
    /// Decodes saved scans and identify output alike. Every field is optional, and a powertrain is read loosely
    /// ("gasoline", "EV"), an unknown one becoming nil, so an odd spelling never fails a whole identify call.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(massKg: try container.decodeIfPresent(Double.self, forKey: .massKg),
                  servingKg: try container.decodeIfPresent(Double.self, forKey: .servingKg),
                  packagingMassG: try container.decodeIfPresent(Double.self, forKey: .packagingMassG),
                  screenSizeInches: try container.decodeIfPresent(Double.self, forKey: .screenSizeInches),
                  ratedPowerW: try container.decodeIfPresent(Double.self, forKey: .ratedPowerW),
                  volumeLiters: try container.decodeIfPresent(Double.self, forKey: .volumeLiters),
                  foodGroup: try container.decodeIfPresent(String.self, forKey: .foodGroup),
                  deviceType: try container.decodeIfPresent(String.self, forKey: .deviceType),
                  packNetKg: try container.decodeIfPresent(Double.self, forKey: .packNetKg),
                  cooked: try container.decodeIfPresent(Bool.self, forKey: .cooked),
                  powertrain: (try? container.decodeIfPresent(String.self, forKey: .powertrain))
                      .flatMap(Powertrain.init(looseRawValue:)),
                  consumable: try container.decodeIfPresent(Bool.self, forKey: .consumable),
                  usesPerContainer: try container.decodeIfPresent(Double.self, forKey: .usesPerContainer))
    }
}
