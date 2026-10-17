import GreenCore

/// Human-readable labels for profile answers. Named `profileLabel` / `profileSymbol` so they never collide
/// with display helpers GreenCore may add later.
protocol ProfileOption: Hashable, CaseIterable where AllCases: RandomAccessCollection {
    var profileLabel: String { get }
    var profileSymbol: String { get }
}

extension Diet: ProfileOption {
    var profileLabel: String {
        switch self {
        case .omnivore: "Omnivore"
        case .flexitarian: "Flexitarian"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        }
    }

    var profileSymbol: String {
        switch self {
        case .omnivore: "fork.knife"
        case .flexitarian: "leaf.arrow.triangle.circlepath"
        case .vegetarian: "carrot"
        case .vegan: "leaf"
        }
    }
}

extension CommuteMode: ProfileOption {
    var profileLabel: String {
        switch self {
        case .car: "Car"
        case .electricCar: "Electric car"
        case .transit: "Transit"
        case .bike: "Bike"
        case .eBike: "E-bike"
        case .walk: "Walk"
        case .remote: "Work from home"
        }
    }

    var profileSymbol: String {
        switch self {
        case .car: "car"
        case .electricCar: "bolt.car"
        case .transit: "tram"
        case .bike: "bicycle"
        case .eBike: "bicycle.circle"
        case .walk: "figure.walk"
        case .remote: "house"
        }
    }
}

extension HomeType: ProfileOption {
    var profileLabel: String {
        switch self {
        case .apartment: "Apartment"
        case .townhouse: "Townhouse"
        case .detachedHouse: "Detached house"
        case .dorm: "Dorm"
        }
    }

    var profileSymbol: String {
        switch self {
        case .apartment: "building.2"
        case .townhouse: "house.and.flag"
        case .detachedHouse: "house"
        case .dorm: "bed.double"
        }
    }
}

extension HeatingSource: ProfileOption {
    var profileLabel: String {
        switch self {
        case .naturalGas: "Natural gas"
        case .electricResistance: "Electric heaters"
        case .heatPump: "Heat pump"
        case .oil: "Heating oil"
        case .districtHeating: "District heating"
        case .none: "No heating"
        }
    }

    var profileSymbol: String {
        switch self {
        case .naturalGas: "flame"
        case .electricResistance: "heater.vertical"
        case .heatPump: "fan"
        case .oil: "drop.halffull"
        case .districtHeating: "building.columns"
        case .none: "xmark.circle"
        }
    }
}

extension ClothingHabit: ProfileOption {
    var profileLabel: String {
        switch self {
        case .mostlyNew: "Mostly new"
        case .mixed: "A mix"
        case .mostlySecondHand: "Mostly second-hand"
        }
    }

    var profileSymbol: String {
        switch self {
        case .mostlyNew: "bag"
        case .mixed: "arrow.triangle.2.circlepath"
        case .mostlySecondHand: "arrow.3.trianglepath"
        }
    }
}

extension DeferrableLoadType: ProfileOption {
    var profileLabel: String {
        switch self {
        case .eBike: "E-bike"
        case .eScooter: "E-scooter"
        case .laptopCharger: "Laptop"
        case .powerBank: "Power bank"
        case .dishwasher: "Dishwasher"
        case .washer: "Washing machine"
        case .evCharger: "Electric car"
        }
    }

    var profileSymbol: String {
        switch self {
        case .eBike: "bicycle"
        case .eScooter: "scooter"
        case .laptopCharger: "laptopcomputer"
        case .powerBank: "battery.100percent.bolt"
        case .dishwasher: "dishwasher"
        case .washer: "washer"
        case .evCharger: "ev.charger"
        }
    }
}
