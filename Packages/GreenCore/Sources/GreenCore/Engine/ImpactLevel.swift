/// How large an item's yearly amount is next to one person's year (spec §6 pins and rows). Pins and rows are
/// coloured by this rather than by the item's share of its scene, so a lone 3 g flyer is not painted as an alarm
/// for being 100% of the photo, and a car is not green for sharing it with another car.
public enum ImpactLevel: Int, Sendable, Hashable, CaseIterable, Comparable {
    case low, moderate, high, veryHigh

    public static func < (lhs: ImpactLevel, rhs: ImpactLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Rough yearly totals for one person, in canonical units, that the levels are measured against.
    public static let personYear: [MetricKey: Double] = [
        // kg CO2e: between the world mean (≈ 6.5 t incl. land use, Our World in Data) and the US one
        // (17.5 t, `per_capita.json`).
        .carbon: 10_000,
        // kWh: US residential electricity per person (EIA, ≈ 4,400 kWh).
        .yearlyElectricity: 4_000,
        // L: food's blue-water withdrawals per person worldwide (Poore & Nemecek 2018, ≈ 340 m³).
        .water: 300_000,
        // m²·yr: world agricultural land per person (`per_capita.json`, 5,931).
        .land: 6_000,
        // g: plastic waste per person in high-income countries (OECD Global Plastics Outlook 2022, ≈ 100 kg).
        .plasticMass: 100_000,
        // g PO4e: food's eutrophication per person worldwide (Poore & Nemecek 2018, ≈ 4 kg).
        .waterPollution: 4_000,
    ]

    /// Upper bounds of `low`, `moderate` and `high` as a share of a person's year: under 0.25%, 1% and 3%.
    public static let thresholds = [0.0025, 0.01, 0.03]

    /// The level of a yearly amount, or nil for a metric without a yearly reference.
    public init?(yearly value: Double, metric: MetricKey) {
        guard let reference = Self.personYear[metric], reference > 0 else { return nil }
        let share = max(value, 0) / reference
        let index = Self.thresholds.firstIndex { share < $0 } ?? Self.thresholds.count
        self = Self.allCases[index]
    }
}
