/// Where the user lives; maps to a grid region and per-capita baseline.
public struct Region: Codable, Sendable, Hashable {
    /// ISO 3166-1 alpha-2, e.g. "US".
    public var countryCode: String
    public var postalCode: String?
    /// Two-letter US state code when known.
    public var usState: String?
    /// eGRID subregion (US) or Electricity Maps zone, e.g. "NEWE" / "US-NE-ISNE".
    public var gridZone: String?

    public init(countryCode: String, postalCode: String? = nil, usState: String? = nil, gridZone: String? = nil) {
        self.countryCode = countryCode
        self.postalCode = postalCode
        self.usState = usState
        self.gridZone = gridZone
    }
}

public enum Diet: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
    case omnivore, flexitarian, vegetarian, vegan
}

public enum CommuteMode: String, Codable, Sendable, Hashable, CaseIterable {
    case car, electricCar, transit, bike, eBike, walk, remote
}

public enum HomeType: String, Codable, Sendable, Hashable, CaseIterable {
    case apartment, townhouse, detachedHouse, dorm
}

public enum HeatingSource: String, Codable, Sendable, Hashable, CaseIterable {
    case naturalGas, electricResistance, heatPump, oil, districtHeating, none
}

public enum ClothingHabit: String, Codable, Sendable, Hashable, CaseIterable {
    case mostlyNew, mixed, mostlySecondHand
}

/// Onboarding answers (spec §9); drives the cohort model and prompt context.
public struct UserProfile: Codable, Sendable, Hashable {
    public var region: Region
    public var householdSize: Int
    public var diet: Diet
    public var commuteMode: CommuteMode
    public var commuteKmPerWeek: Double
    public var homeType: HomeType
    public var heating: HeatingSource
    public var clothingHabit: ClothingHabit
    public var chargingItems: Set<DeferrableLoadType>
    public var onboardingCompleted: Bool

    public init(region: Region = Region(countryCode: "US", usState: "MA", gridZone: "US-NE-ISNE"),
                householdSize: Int = 2, diet: Diet = .omnivore, commuteMode: CommuteMode = .transit,
                commuteKmPerWeek: Double = 50, homeType: HomeType = .apartment, heating: HeatingSource = .naturalGas,
                clothingHabit: ClothingHabit = .mixed, chargingItems: Set<DeferrableLoadType> = [],
                onboardingCompleted: Bool = false) {
        self.region = region
        self.householdSize = householdSize
        self.diet = diet
        self.commuteMode = commuteMode
        self.commuteKmPerWeek = commuteKmPerWeek
        self.homeType = homeType
        self.heating = heating
        self.clothingHabit = clothingHabit
        self.chargingItems = chargingItems
        self.onboardingCompleted = onboardingCompleted
    }

    public static let `default` = UserProfile()

    /// One-paragraph summary passed to Claude as context.
    public var promptSummary: String {
        var parts = ["Lives in \(region.usState.map { "\($0), " } ?? "")\(region.countryCode)"]
        parts.append("household of \(householdSize)")
        parts.append("\(diet.rawValue) diet")
        parts.append("commutes by \(commuteMode.rawValue) ~\(Int(commuteKmPerWeek)) km/week")
        parts.append("\(homeType.rawValue) heated by \(heating.rawValue)")
        parts.append("buys clothing \(clothingHabit.rawValue)")
        if !chargingItems.isEmpty {
            parts.append("owns " + chargingItems.map(\.rawValue).sorted().joined(separator: ", "))
        }
        return parts.joined(separator: "; ") + "."
    }
}
