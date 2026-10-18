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

    public init(massKg: Double? = nil, servingKg: Double? = nil, packagingMassG: Double? = nil,
                screenSizeInches: Double? = nil, ratedPowerW: Double? = nil, volumeLiters: Double? = nil,
                foodGroup: String? = nil, deviceType: String? = nil, packNetKg: Double? = nil) {
        self.massKg = massKg
        self.servingKg = servingKg
        self.packagingMassG = packagingMassG
        self.screenSizeInches = screenSizeInches
        self.ratedPowerW = ratedPowerW
        self.volumeLiters = volumeLiters
        self.foodGroup = foodGroup
        self.deviceType = deviceType
        self.packNetKg = packNetKg
    }
}
