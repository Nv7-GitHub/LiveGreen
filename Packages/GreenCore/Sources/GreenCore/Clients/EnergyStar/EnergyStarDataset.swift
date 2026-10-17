import Foundation

/// One ENERGY STAR certified-products dataset on data.energystar.gov (Socrata), with the columns that
/// hold its model identifiers and power figures. Ids and field names come from the live catalog
/// (`/api/views/{id}.json`).
public struct EnergyStarDataset: Sendable, Hashable {
    public var id: String
    public var name: String
    public var productType: String
    public var modelColumns: [String]
    public var onModeColumn: String?
    /// Tried in order; the first present value wins.
    public var standbyColumns: [String]
    public var annualKWhColumn: String?
    /// `Quantities.deviceType` keys this dataset covers, used to narrow lookups.
    public var deviceTypes: Set<String>

    public init(id: String, name: String, productType: String, modelColumns: [String], onModeColumn: String? = nil,
                standbyColumns: [String] = [], annualKWhColumn: String? = nil, deviceTypes: Set<String>) {
        self.id = id
        self.name = name
        self.productType = productType
        self.modelColumns = modelColumns
        self.onModeColumn = onModeColumn
        self.standbyColumns = standbyColumns
        self.annualKWhColumn = annualKWhColumn
        self.deviceTypes = deviceTypes
    }

    static let allModelColumns = ["model_number", "model_name", "additional_model_information"]
    static let numberColumns = ["model_number", "additional_model_information"]

    public static let televisions = EnergyStarDataset(
        id: "pd96-rr3d", name: "ENERGY STAR Certified Televisions", productType: "Televisions",
        modelColumns: allModelColumns, onModeColumn: "power_consumption_in_on_mode_watts",
        standbyColumns: ["power_consumption_in_standby_mode_when_network_connected_watts",
                         "power_consumption_in_standby_mode_when_network_not_connected_watts", "measured_standby_mode_power_w"],
        annualKWhColumn: "reported_annual_energy_consumption_kwh", deviceTypes: ["television", "tv"])

    public static let displays = EnergyStarDataset(
        id: "qbg3-d468", name: "ENERGY STAR Certified Displays", productType: "Monitors",
        modelColumns: allModelColumns, onModeColumn: "on_mode_power_watts", standbyColumns: ["sleep_mode_power_watts"],
        deviceTypes: ["monitor", "display"])

    /// Computers report idle power rather than an active on-mode figure; short idle is the closest proxy.
    public static let computers = EnergyStarDataset(
        id: "rxdj-2c88", name: "ENERGY STAR Certified Computers", productType: "Computers",
        modelColumns: allModelColumns, onModeColumn: "short_idle_watts", standbyColumns: ["sleep_mode_watts", "off_mode_watts"],
        annualKWhColumn: "tec_of_model_kwh", deviceTypes: ["laptop", "desktop", "computer", "all_in_one"])

    public static let refrigerators = EnergyStarDataset(
        id: "p5st-her9", name: "ENERGY STAR Certified Residential Refrigerators", productType: "Refrigerators",
        modelColumns: numberColumns, annualKWhColumn: "annual_energy_use_kwh_yr", deviceTypes: ["refrigerator", "fridge"])

    public static let freezers = EnergyStarDataset(
        id: "8t9c-g3tn", name: "ENERGY STAR Certified Residential Freezers", productType: "Freezers",
        modelColumns: numberColumns, annualKWhColumn: "annual_energy_use_kwh_yr", deviceTypes: ["freezer"])

    public static let dishwashers = EnergyStarDataset(
        id: "q8py-6w3f", name: "ENERGY STAR Certified Residential Dishwashers", productType: "Dishwashers",
        modelColumns: numberColumns, annualKWhColumn: "annual_energy_use_kwh_year", deviceTypes: ["dishwasher"])

    public static let clothesWashers = EnergyStarDataset(
        id: "bghd-e2wd", name: "ENERGY STAR Certified Residential Clothes Washers", productType: "Clothes Washers",
        modelColumns: numberColumns, annualKWhColumn: "annual_energy_use_kwh_year", deviceTypes: ["washer", "washing_machine"])

    public static let clothesDryers = EnergyStarDataset(
        id: "t9u7-4d2j", name: "ENERGY STAR Certified Residential Clothes Dryers", productType: "Clothes Dryers",
        modelColumns: allModelColumns, annualKWhColumn: "estimated_annual_energy_use_kwh_yr", deviceTypes: ["dryer"])

    public static let roomAirCleaners = EnergyStarDataset(
        id: "gaa3-swy6", name: "ENERGY STAR Certified Room Air Cleaners", productType: "Room Air Cleaners",
        modelColumns: allModelColumns, annualKWhColumn: "annual_energy_use_kwh_yr", deviceTypes: ["air_purifier", "air_cleaner"])

    public static let dehumidifiers = EnergyStarDataset(
        id: "mgiu-hu4z", name: "ENERGY STAR Certified Dehumidifiers", productType: "Dehumidifiers",
        modelColumns: numberColumns, annualKWhColumn: "annual_energy_consumption_kwh_yr", deviceTypes: ["dehumidifier"])

    public static let roomAirConditioners = EnergyStarDataset(
        id: "5xn2-dv4h", name: "ENERGY STAR Certified Room Air Conditioners", productType: "Room Air Conditioners",
        modelColumns: numberColumns, annualKWhColumn: "annual_energy_use_kwh_yr", deviceTypes: ["air_conditioner"])

    public static let evChargers = EnergyStarDataset(
        id: "5jwe-c8xm", name: "ENERGY STAR Certified Electric Vehicle Supply Equipment (AC)", productType: "EV Chargers",
        modelColumns: allModelColumns, standbyColumns: ["no_vehicle_mode_input_power_w", "idle_mode_input_power_w"],
        deviceTypes: ["ev_charger"])

    public static let imagingEquipment = EnergyStarDataset(
        id: "t2v6-g4nf", name: "ENERGY STAR Certified Imaging Equipment", productType: "Printers & Copiers",
        modelColumns: allModelColumns, standbyColumns: ["power_in_sleep_w", "power_in_standby_w"],
        annualKWhColumn: "typical_electricity_consumption_tec_kwh_yr", deviceTypes: ["printer", "copier", "scanner"])

    public static let all: [EnergyStarDataset] = [
        televisions, displays, computers, refrigerators, freezers, dishwashers, clothesWashers, clothesDryers,
        roomAirCleaners, dehumidifiers, roomAirConditioners, evChargers, imagingEquipment,
    ]

    /// Datasets for a device type, or all of them when the type is unknown or unmatched.
    public static func datasets(forDeviceType deviceType: String?) -> [EnergyStarDataset] {
        guard let key = deviceType?.lowercased() else { return all }
        let matches = all.filter { $0.deviceTypes.contains(key) }
        return matches.isEmpty ? all : matches
    }
}
