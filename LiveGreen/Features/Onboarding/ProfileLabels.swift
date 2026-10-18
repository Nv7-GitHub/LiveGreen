import Foundation
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
        case .eBike: "E-bike"
        }
    }

    var profileSymbol: String {
        switch self {
        case .car: "car"
        case .electricCar: "bolt.car"
        case .transit: "tram"
        case .eBike: "bicycle.circle"
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

extension HomeType {
    /// Average floor area for this type of home (EIA RECS 2020), m².
    var typicalFloorAreaM2: Double {
        ReferenceStore.bundled.cohort.homeSize.typicalFloorAreaM2[self] ?? 100
    }
}

extension UserProfile {
    /// The answered floor area, or the typical one for the home type until it is answered.
    var shownFloorAreaM2: Double { floorAreaM2 ?? homeType.typicalFloorAreaM2 }

    /// "Natural gas + Heat pump", or "No heating".
    var heatingLabel: String {
        let sources = orderedHeatingSources
        return sources.isEmpty ? HeatingSource.none.profileLabel : sources.map(\.profileLabel).joined(separator: " + ")
    }
}

/// Floor areas in ft² (imperial) or m², rounded to a sensible step.
enum FloorAreaFormat {
    static func text(m2: Double) -> String {
        if DisplayUnits.system == .imperial {
            let squareFeet = (m2 * DisplayUnits.squareFeetPerSquareMeter / 50).rounded() * 50
            return "\(Int(squareFeet).formatted()) ft²"
        }
        return "\(Int((m2 / 5).rounded() * 5).formatted()) m²"
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
