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
    /// Weekly distance per way of getting around; several modes can be in use at once (car + transit + bike).
    public var commuteKmPerWeekByMode: [CommuteMode: Double]
    public var homeType: HomeType
    public var heating: HeatingSource
    public var clothingHabit: ClothingHabit
    public var chargingItems: Set<DeferrableLoadType>
    public var onboardingCompleted: Bool

    public init(region: Region = Region(countryCode: "US", usState: "MA", gridZone: "US-NE-ISNE"),
                householdSize: Int = 2, diet: Diet = .omnivore, commuteMode: CommuteMode = .transit,
                commuteKmPerWeek: Double = 50, commuteKmPerWeekByMode: [CommuteMode: Double]? = nil,
                homeType: HomeType = .apartment, heating: HeatingSource = .naturalGas,
                clothingHabit: ClothingHabit = .mixed, chargingItems: Set<DeferrableLoadType> = [],
                onboardingCompleted: Bool = false) {
        self.region = region
        self.householdSize = householdSize
        self.diet = diet
        self.commuteKmPerWeekByMode = commuteKmPerWeekByMode ?? [commuteMode: commuteMode == .remote ? 0 : commuteKmPerWeek]
        self.homeType = homeType
        self.heating = heating
        self.clothingHabit = clothingHabit
        self.chargingItems = chargingItems
        self.onboardingCompleted = onboardingCompleted
    }

    public static let `default` = UserProfile()

    /// The modes in use, longest weekly distance first.
    public var commuteModes: [CommuteMode] {
        commuteKmPerWeekByMode.keys.sorted {
            (commuteKmPerWeekByMode[$0] ?? 0, $1.rawValue) > (commuteKmPerWeekByMode[$1] ?? 0, $0.rawValue)
        }
    }

    /// The main way of getting around (longest weekly distance); `.remote` when nothing is selected.
    public var commuteMode: CommuteMode { commuteModes.first ?? .remote }

    /// Total weekly distance across modes.
    public var commuteKmPerWeek: Double { commuteKmPerWeekByMode.values.reduce(0, +) }

    private enum CodingKeys: String, CodingKey {
        case region, householdSize, diet, commuteKmPerWeekByMode, commuteMode, commuteKmPerWeek, homeType, heating
        case clothingHabit, chargingItems, onboardingCompleted
    }

    /// Profiles saved before multi-mode commutes stored one `commuteMode` and `commuteKmPerWeek`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = try container.decode(Region.self, forKey: .region)
        householdSize = try container.decode(Int.self, forKey: .householdSize)
        diet = try container.decode(Diet.self, forKey: .diet)
        if let byMode = try container.decodeIfPresent([CommuteMode: Double].self, forKey: .commuteKmPerWeekByMode) {
            commuteKmPerWeekByMode = byMode
        } else {
            let mode = try container.decodeIfPresent(CommuteMode.self, forKey: .commuteMode) ?? .transit
            let km = try container.decodeIfPresent(Double.self, forKey: .commuteKmPerWeek) ?? 0
            commuteKmPerWeekByMode = [mode: mode == .remote ? 0 : km]
        }
        homeType = try container.decode(HomeType.self, forKey: .homeType)
        heating = try container.decode(HeatingSource.self, forKey: .heating)
        clothingHabit = try container.decode(ClothingHabit.self, forKey: .clothingHabit)
        chargingItems = try container.decode(Set<DeferrableLoadType>.self, forKey: .chargingItems)
        onboardingCompleted = try container.decode(Bool.self, forKey: .onboardingCompleted)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(region, forKey: .region)
        try container.encode(householdSize, forKey: .householdSize)
        try container.encode(diet, forKey: .diet)
        try container.encode(commuteKmPerWeekByMode, forKey: .commuteKmPerWeekByMode)
        try container.encode(homeType, forKey: .homeType)
        try container.encode(heating, forKey: .heating)
        try container.encode(clothingHabit, forKey: .clothingHabit)
        try container.encode(chargingItems, forKey: .chargingItems)
        try container.encode(onboardingCompleted, forKey: .onboardingCompleted)
    }

    /// One-paragraph summary passed to Claude as context.
    public var promptSummary: String {
        var parts = ["Lives in \(region.usState.map { "\($0), " } ?? "")\(region.countryCode)"]
        parts.append("household of \(householdSize)")
        parts.append("\(diet.rawValue) diet")
        let commute = commuteModes.map { "\($0.rawValue) ~\(Int(commuteKmPerWeekByMode[$0] ?? 0)) km/week" }
        parts.append(commute.isEmpty ? "no regular commute" : "gets around by " + commute.joined(separator: ", "))
        parts.append("\(homeType.rawValue) heated by \(heating.rawValue)")
        parts.append("buys clothing \(clothingHabit.rawValue)")
        if !chargingItems.isEmpty {
            parts.append("owns " + chargingItems.map(\.rawValue).sorted().joined(separator: ", "))
        }
        return parts.joined(separator: "; ") + "."
    }
}
