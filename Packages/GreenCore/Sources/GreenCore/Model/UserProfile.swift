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

/// The eating pattern a profile's meat and dairy meal counts amount to (`UserProfile.diet`).
public enum Diet: String, Codable, Sendable, Hashable, CaseIterable, CodingKeyRepresentable {
    case omnivore, flexitarian, vegetarian, vegan

    /// Meals a week with meat and with dairy standing in for this pattern, for profiles saved before meal
    /// counts: each maps to about the food footprint its old modifier gave (1, 0.83, 0.68, 0.51 of average).
    public var typicalMealsPerWeek: (meat: Int, dairy: Int) {
        switch self {
        case .omnivore: (9, 10)
        case .flexitarian: (5, 10)
        case .vegetarian: (0, 14)
        case .vegan: (0, 0)
        }
    }
}

/// Ways of getting around that emit carbon. Walking, cycling and working from home were options in older
/// builds; they add nothing, so profiles that saved them decode to no distance for those modes.
public enum CommuteMode: String, Codable, Sendable, Hashable, CaseIterable {
    case car, electricCar, transit, eBike
}

public enum HomeType: String, Codable, Sendable, Hashable, CaseIterable {
    case apartment, townhouse, detachedHouse, dorm
}

/// A space-heating source. `none` is the "no heating" answer and the reference key for unheated homes;
/// `UserProfile.heatingSources` leaves it out (an empty set means no heating).
public enum HeatingSource: String, Codable, Sendable, Hashable, CaseIterable {
    case naturalGas, electricResistance, heatPump, oil, districtHeating, none
}

/// Onboarding answers (spec §9); drives the cohort model and prompt context.
public struct UserProfile: Codable, Sendable, Hashable {
    /// Meal counts are per week of 21 meals.
    public static let mealsPerWeek = 21
    /// Typical answers, matching the reference averages (`CohortReference.meals`, `.clothing`), so a profile
    /// left at its defaults gets the regional average for food and clothing.
    public static let typicalMeatMealsPerWeek = 9
    public static let typicalDairyMealsPerWeek = 10
    public static let typicalNewClothesPerYear = 64.0

    public var region: Region
    public var householdSize: Int
    /// Meals in a typical week (0–21) where meat, poultry or fish is an important component.
    public var meatMealsPerWeek: Int
    /// Meals in a typical week (0–21) where dairy (cheese, milk, yogurt, cream) is an important component.
    public var dairyMealsPerWeek: Int
    /// Weekly distance per way of getting around; several modes can be in use at once (car + transit).
    /// Empty means no regular travel that emits carbon.
    public var commuteKmPerWeekByMode: [CommuteMode: Double]
    public var homeType: HomeType
    /// Approximate floor area of the whole home, m² (shown in ft² in imperial units). Nil until answered,
    /// which counts as the typical area for the home type.
    public var floorAreaM2: Double?
    /// Every heating source in use, weighted evenly in calculations. Empty means no heating.
    public var heatingSources: Set<HeatingSource>
    /// New clothing items (garments, not second-hand) bought in a year.
    public var newClothesPerYear: Double
    public var chargingItems: Set<DeferrableLoadType>
    public var onboardingCompleted: Bool

    public init(region: Region = Region(countryCode: "US", usState: "MA", gridZone: "US-NE-ISNE"),
                householdSize: Int = 2, meatMealsPerWeek: Int = typicalMeatMealsPerWeek,
                dairyMealsPerWeek: Int = typicalDairyMealsPerWeek, commuteMode: CommuteMode = .transit,
                commuteKmPerWeek: Double = 50, commuteKmPerWeekByMode: [CommuteMode: Double]? = nil,
                homeType: HomeType = .apartment, floorAreaM2: Double? = nil,
                heatingSources: Set<HeatingSource> = [.naturalGas], newClothesPerYear: Double = typicalNewClothesPerYear,
                chargingItems: Set<DeferrableLoadType> = [], onboardingCompleted: Bool = false) {
        self.region = region
        self.householdSize = householdSize
        self.meatMealsPerWeek = Self.clampedMeals(meatMealsPerWeek)
        self.dairyMealsPerWeek = Self.clampedMeals(dairyMealsPerWeek)
        self.commuteKmPerWeekByMode = commuteKmPerWeekByMode ?? [commuteMode: commuteKmPerWeek]
        self.homeType = homeType
        self.floorAreaM2 = floorAreaM2
        self.heatingSources = heatingSources.subtracting([.none])
        self.newClothesPerYear = max(0, newClothesPerYear)
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

    /// The main way of getting around (longest weekly distance); nil when nothing is selected.
    public var commuteMode: CommuteMode? { commuteModes.first }

    /// Total weekly distance across modes.
    public var commuteKmPerWeek: Double { commuteKmPerWeekByMode.values.reduce(0, +) }

    /// The eating pattern the meal counts amount to: no meat or dairy is vegan, no meat vegetarian, meat in
    /// fewer than one meal a day flexitarian.
    public var diet: Diet {
        switch (meatMealsPerWeek, dairyMealsPerWeek) {
        case (0, 0): .vegan
        case (0, _): .vegetarian
        case (..<7, _): .flexitarian
        default: .omnivore
        }
    }

    /// Heating sources in a stable order, for labels and prompts.
    public var orderedHeatingSources: [HeatingSource] {
        HeatingSource.allCases.filter { heatingSources.contains($0) && $0 != .none }
    }

    private static func clampedMeals(_ count: Int) -> Int { min(max(count, 0), mealsPerWeek) }

    private enum CodingKeys: String, CodingKey {
        case region, householdSize, meatMealsPerWeek, dairyMealsPerWeek, commuteKmPerWeekByMode, homeType
        case floorAreaM2, heatingSources, newClothesPerYear, chargingItems, onboardingCompleted
        /// Older builds: one diet, one commute mode and distance, one heating source, a clothing habit.
        case diet, commuteMode, commuteKmPerWeek, heating, clothingHabit
    }

    /// New clothes a year standing in for the clothing habit older builds asked about, matching the
    /// footprint each habit's modifier gave (1.25, 1 and 0.6 of average) under `ClothingFactors`.
    private static let legacyNewClothesPerYear: [String: Double] = [
        "mostlyNew": 83, "mixed": typicalNewClothesPerYear, "mostlySecondHand": 34,
    ]

    /// Decodes profiles from every build. Older ones stored a diet label, one commute mode and distance (or
    /// walk, bike and work from home, which add nothing), one heating source and a clothing habit; each maps
    /// to the closest current answer. Missing new fields take their defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = try container.decode(Region.self, forKey: .region)
        householdSize = try container.decode(Int.self, forKey: .householdSize)

        let legacyDiet = try container.decodeIfPresent(String.self, forKey: .diet).flatMap(Diet.init(rawValue:))
        let meals = legacyDiet?.typicalMealsPerWeek ?? (meat: Self.typicalMeatMealsPerWeek, dairy: Self.typicalDairyMealsPerWeek)
        meatMealsPerWeek = Self.clampedMeals(try container.decodeIfPresent(Int.self, forKey: .meatMealsPerWeek) ?? meals.meat)
        dairyMealsPerWeek = Self.clampedMeals(try container.decodeIfPresent(Int.self, forKey: .dairyMealsPerWeek) ?? meals.dairy)

        if container.contains(.commuteKmPerWeekByMode) {
            // A `[CommuteMode: Double]` encodes as [mode, km, mode, km…]; modes that no longer exist are skipped.
            var pairs = try container.nestedUnkeyedContainer(forKey: .commuteKmPerWeekByMode)
            var byMode: [CommuteMode: Double] = [:]
            while !pairs.isAtEnd {
                let mode = try pairs.decode(String.self)
                let km = try pairs.decode(Double.self)
                if let mode = CommuteMode(rawValue: mode) { byMode[mode] = km }
            }
            commuteKmPerWeekByMode = byMode
        } else {
            let mode = try container.decodeIfPresent(String.self, forKey: .commuteMode) ?? CommuteMode.transit.rawValue
            let km = try container.decodeIfPresent(Double.self, forKey: .commuteKmPerWeek) ?? 0
            commuteKmPerWeekByMode = CommuteMode(rawValue: mode).map { [$0: km] } ?? [:]
        }

        homeType = try container.decode(HomeType.self, forKey: .homeType)
        floorAreaM2 = try container.decodeIfPresent(Double.self, forKey: .floorAreaM2)
        if let sources = try container.decodeIfPresent(Set<HeatingSource>.self, forKey: .heatingSources) {
            heatingSources = sources.subtracting([.none])
        } else {
            let single = try container.decodeIfPresent(HeatingSource.self, forKey: .heating) ?? .naturalGas
            heatingSources = Set([single]).subtracting([.none])
        }

        if let perYear = try container.decodeIfPresent(Double.self, forKey: .newClothesPerYear) {
            newClothesPerYear = max(0, perYear)
        } else {
            let habit = try container.decodeIfPresent(String.self, forKey: .clothingHabit)
            newClothesPerYear = habit.flatMap { Self.legacyNewClothesPerYear[$0] } ?? Self.typicalNewClothesPerYear
        }
        chargingItems = try container.decode(Set<DeferrableLoadType>.self, forKey: .chargingItems)
        onboardingCompleted = try container.decode(Bool.self, forKey: .onboardingCompleted)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(region, forKey: .region)
        try container.encode(householdSize, forKey: .householdSize)
        try container.encode(meatMealsPerWeek, forKey: .meatMealsPerWeek)
        try container.encode(dairyMealsPerWeek, forKey: .dairyMealsPerWeek)
        try container.encode(commuteKmPerWeekByMode, forKey: .commuteKmPerWeekByMode)
        try container.encode(homeType, forKey: .homeType)
        try container.encodeIfPresent(floorAreaM2, forKey: .floorAreaM2)
        try container.encode(orderedHeatingSources, forKey: .heatingSources)
        try container.encode(newClothesPerYear, forKey: .newClothesPerYear)
        try container.encode(chargingItems, forKey: .chargingItems)
        try container.encode(onboardingCompleted, forKey: .onboardingCompleted)
    }

    /// One-paragraph summary passed to Claude as context.
    public var promptSummary: String {
        var parts = ["Lives in \(region.usState.map { "\($0), " } ?? "")\(region.countryCode)"]
        parts.append("household of \(householdSize)")
        parts.append("eats meat in ~\(meatMealsPerWeek) and dairy in ~\(dairyMealsPerWeek) of \(Self.mealsPerWeek) "
                     + "meals a week (\(diet.rawValue))")
        let commute = commuteModes.map { "\($0.rawValue) ~\(Int(commuteKmPerWeekByMode[$0] ?? 0)) km/week" }
        parts.append(commute.isEmpty ? "no regular travel by car or transit" : "gets around by " + commute.joined(separator: ", "))
        let size = floorAreaM2.map { " of ~\(Int($0.rounded())) m²" } ?? ""
        let heating = orderedHeatingSources.map(\.rawValue)
        parts.append("\(homeType.rawValue)\(size) " + (heating.isEmpty ? "with no heating" : "heated by " + heating.joined(separator: " and ")))
        parts.append("buys ~\(Int(newClothesPerYear.rounded())) new clothing items a year")
        if !chargingItems.isEmpty {
            parts.append("owns " + chargingItems.map(\.rawValue).sorted().joined(separator: ", "))
        }
        return parts.joined(separator: "; ") + "."
    }
}
