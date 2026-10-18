import Foundation

/// An everyday comparison for an amount ("driving 1,200 miles in an average gas car"), so a yearly footprint or
/// a saving reads as something people know. Each comes from a cited factor in `Equivalences.factors`.
public struct Equivalence: Sendable, Hashable {
    /// `Equivalences.Factor.id`, so screens showing several can avoid repeats.
    public var id: String
    public var metric: MetricKey
    /// SF Symbol for the thing compared with.
    public var systemImage: String
    /// How many of the thing the amount comes to.
    public var count: Double
    /// The comparison, to follow an opening: "driving 1,200 miles in an average gas car".
    public var phrase: String
    /// Which of `Equivalences.openings` the sentence starts with, so the wording varies with the comparison.
    public var opening = 0
    /// Where the factor comes from.
    public var source: String

    /// Whether the number is an amount (a footprint) or an amount saved.
    public enum Framing: Sendable {
        case amount, saving
    }

    /// "That's like driving 1,200 miles in an average gas car!", or for a saving "That saves as much as …!".
    public func sentence(_ framing: Framing = .amount) -> String {
        let openings = Equivalences.openings(framing)
        return "\(openings[opening % openings.count]) \(phrase)!"
    }
}

public enum Equivalences {
    /// How a comparison opens; `pick` varies it along with the comparison.
    public static func openings(_ framing: Equivalence.Framing) -> [String] {
        switch framing {
        case .amount: ["That's like", "That's equivalent to", "That's about the same as"]
        case .saving: ["That saves as much as", "That's a saving equal to", "You'd save about as much as"]
        }
    }

    /// One kind of comparison for one metric.
    public struct Factor: Sendable {
        /// The thing in one unit system: canonical metric units per thing and how to say it ("{n}" is the count).
        public struct Wording: Sendable {
            public var amount: Double
            public var one: String
            public var many: String
        }

        public var id: String
        public var metric: MetricKey
        public var systemImage: String
        public var imperial: Wording
        /// Nil when the thing is the same in both systems.
        public var metricWording: Wording?
        /// Counts it reads well at: below, it is a fraction of a thing; above, another comparison suits better (no
        /// "for 720 days": a day count stops at a year, or a few months where a per-year version exists).
        public var readable: ClosedRange<Double>
        public var source: String

        func wording(imperial isImperial: Bool) -> Wording { isImperial ? imperial : metricWording ?? imperial }
    }

    private static func factor(_ id: String, _ metric: MetricKey, _ systemImage: String, readable: ClosedRange<Double>,
                               _ imperial: Factor.Wording, metric metricWording: Factor.Wording? = nil,
                               source: String) -> Factor {
        Factor(id: id, metric: metric, systemImage: systemImage, imperial: imperial, metricWording: metricWording,
               readable: readable, source: source)
    }

    private static func say(_ amount: Double, _ one: String, _ many: String) -> Factor.Wording {
        Factor.Wording(amount: amount, one: one, many: many)
    }

    private static let litersPerGallon = 3.785_41
    private static let kmPerMile = 1.609_344
    private static let epaCalculator = "US EPA, Greenhouse Gas Equivalencies Calculator (2026)"

    /// Every comparison, in canonical units (kg CO₂e, L, m² held for a year, kWh, g).
    public static let factors: [Factor] = [
        // Carbon, kg CO₂e.
        factor("car", .carbon, "car.fill", readable: 1...500_000,
               say(0.393, "driving {n} mile in an average gas car", "driving {n} miles in an average gas car"),
               metric: say(0.393 / kmPerMile, "driving {n} km in an average gas car", "driving {n} km in an average gas car"),
               source: "\(epaCalculator): 3.93 × 10⁻⁴ t CO₂e per mile in an average gas car"),
        factor("phoneCarbon", .carbon, "iphone", readable: 2...5_000_000,
               say(0.012_4, "charging a smartphone once", "charging a smartphone {n} times"),
               source: "\(epaCalculator): 1.24 × 10⁻⁵ t CO₂ per smartphone charge"),
        factor("seedlings", .carbon, "tree.fill", readable: 1...1_000_000,
               say(60, "what one tree seedling soaks up in 10 years of growing",
                   "what {n} tree seedlings soak up in 10 years of growing"),
               source: "\(epaCalculator): 0.060 t CO₂ per urban tree seedling grown for 10 years"),
        factor("gasoline", .carbon, "fuelpump.fill", readable: 1...1_000_000,
               say(8.887, "burning {n} gallon of gasoline", "burning {n} gallons of gasoline"),
               metric: say(8.887 / litersPerGallon, "burning {n} liter of gasoline", "burning {n} liters of gasoline"),
               source: "\(epaCalculator): 8.887 kg CO₂ per gallon of gasoline"),
        factor("grill", .carbon, "flame.fill", readable: 1...100_000,
               say(22, "using up one backyard-grill propane tank", "using up {n} backyard-grill propane tanks"),
               source: "\(epaCalculator): 0.022 t CO₂ per propane cylinder for home barbecues"),
        factor("homeDays", .carbon, "house.fill", readable: 1...120,
               say(4_798 / 365, "the CO₂ from an average US home's electricity for a day",
                   "the CO₂ from an average US home's electricity for {n} days"),
               source: "\(epaCalculator): 4.798 t CO₂ per home's electricity for a year"),
        factor("homeYears", .carbon, "house.fill", readable: 1...100_000,
               say(4_798, "the CO₂ from an average US home's electricity for a year",
                   "the CO₂ from {n} average US homes' electricity for a year"),
               source: "\(epaCalculator): 4.798 t CO₂ per home's electricity for a year"),

        // Water, L.
        factor("showers", .water, "shower.fill", readable: 1...1_000_000,
               say(15.8 * litersPerGallon, "taking one average shower", "taking {n} average showers"),
               source: "Water Research Foundation, Residential End Uses of Water v2 (2016): 15.8 gal per average US shower"),
        factor("flushes", .water, "toilet.fill", readable: 2...1_000_000,
               say(1.6 * litersPerGallon, "flushing a toilet once", "flushing a toilet {n} times"),
               source: "US federal toilet standard (Energy Policy Act of 1992): 1.6 gal per flush"),
        factor("glasses", .water, "waterbottle.fill", readable: 2...1_000_000,
               say(8 / 33.814, "drinking one glass of water", "drinking {n} glasses of water"),
               metric: say(0.25, "drinking one glass of water", "drinking {n} glasses of water"),
               source: "An 8 fl oz (250 mL) glass"),
        factor("homeWater", .water, "house.fill", readable: 1...365,
               say(82 * litersPerGallon, "the water a typical American uses at home in a day",
                   "the water a typical American uses at home in {n} days"),
               source: "US EPA WaterSense, from USGS: 82 gal a day per person at home"),
        factor("pools", .water, "figure.pool.swim", readable: 1...100_000,
               say(2_500_000, "filling one Olympic swimming pool", "filling {n} Olympic swimming pools"),
               source: "An Olympic pool, 50 × 25 × 2 m (World Aquatics minimum depth)"),

        // Land, m² held for a year.
        factor("yogaMats", .land, "figure.yoga", readable: 1...200,
               say(68 * 24 * 0.000_645_16, "the space of one yoga mat in use all year",
                   "the space of {n} yoga mats in use all year"),
               source: "A standard 68 × 24 in yoga mat"),
        factor("parking", .land, "parkingsign", readable: 1...2_000,
               say(9 * 18 * 0.092_903, "a parking space in use all year", "{n} parking spaces in use all year"),
               source: "A standard 9 × 18 ft parking space"),
        factor("tennis", .land, "tennis.racket", readable: 1...10_000,
               say(23.77 * 10.97, "a tennis court in use all year", "{n} tennis courts in use all year"),
               source: "ITF Rules of Tennis: doubles court 23.77 × 10.97 m"),
        factor("basketball", .land, "basketball.fill", readable: 1...10_000,
               say(94 * 50 * 0.092_903, "an NBA basketball court in use all year",
                   "{n} NBA basketball courts in use all year"),
               source: "NBA rules: court 94 × 50 ft"),
        factor("football", .land, "football.fill", readable: 1...10_000,
               say(360 * 160 * 0.092_903, "an American football field in use all year",
                   "{n} American football fields in use all year"),
               source: "NFL rules: field 360 × 160 ft with end zones"),

        // Electricity, kWh.
        factor("phoneEnergy", .yearlyElectricity, "iphone", readable: 2...5_000_000,
               say(0.019, "charging a smartphone once", "charging a smartphone {n} times"),
               source: "\(epaCalculator): 0.019 kWh per smartphone charge"),
        factor("ledDays", .yearlyElectricity, "lightbulb.led.fill", readable: 1...365,
               say(0.24, "keeping a 10-watt LED bulb on for a day", "keeping a 10-watt LED bulb on for {n} days"),
               source: "A 10 W LED bulb on around the clock (0.24 kWh a day)"),
        factor("homeEnergyDays", .yearlyElectricity, "house.fill", readable: 1...365,
               say(10_791 / 365, "the electricity an average US home uses in a day",
                   "the electricity an average US home uses in {n} days"),
               source: "US EIA: 10,791 kWh a year per US home (2022)"),
        factor("microwave", .yearlyElectricity, "microwave.fill", readable: 1...10_000,
               say(1, "running a 1,000-watt microwave for an hour", "running a 1,000-watt microwave for {n} hours"),
               source: "A 1,000 W microwave (1 kWh an hour)"),

        // Plastic, g.
        factor("bottles", .plasticMass, "waterbottle.fill", readable: 1...10_000_000,
               say(12.7, "one single-use plastic water bottle", "{n} single-use plastic water bottles"),
               source: "Beverage Marketing Corp. for IBWA (2010): 12.7 g per 16.9 oz (500 mL) PET water bottle"),
    ]

    /// Every comparison that reads well for `amount` of `metric` (canonical units).
    public static func candidates(for metric: MetricKey, amount: Double, imperial: Bool) -> [Equivalence] {
        guard amount.isFinite, amount > 0 else { return [] }
        return factors.compactMap { factor in
            guard factor.metric == metric else { return nil }
            let wording = factor.wording(imperial: imperial)
            let count = amount / wording.amount
            guard factor.readable.contains(count) else { return nil }
            let number = format(count)
            let phrase = (number == "1" ? wording.one : wording.many).replacingOccurrences(of: "{n}", with: number)
            return Equivalence(id: factor.id, metric: metric, systemImage: factor.systemImage, count: count,
                               phrase: phrase, source: factor.source)
        }
    }

    /// One comparison for the amount, chosen by `seed` (see `seed(_:on:)`) so it varies between screens, items
    /// and days but holds still while one is on screen. `avoiding` skips comparisons already shown nearby.
    public static func pick(for metric: MetricKey, amount: Double, imperial: Bool, seed: UInt64,
                            avoiding: Set<String> = []) -> Equivalence? {
        let all = candidates(for: metric, amount: amount, imperial: imperial)
        let fresh = all.filter { !avoiding.contains($0.id) }
        let options = fresh.isEmpty ? all : fresh
        guard !options.isEmpty else { return nil }
        var mixer = SplitMix64(seed: seed)
        var chosen = options[Int(mixer.next() % UInt64(options.count))]
        chosen.opening = Int(mixer.next() % 3)
        return chosen
    }

    /// A seed for `pick` from what is on screen (an item, a metric, a card) and the day, so the comparison
    /// changes from day to day and between items, never on every redraw.
    public static func seed(_ context: String, on date: Date = Date(), calendar: Calendar = .current) -> UInt64 {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return StableHash.fnv1a("\(context)|\(day)")
    }

    /// A count as people would say it: "2.5", "40", "1,200", "3.4 million".
    public static func format(_ count: Double) -> String {
        let english = Locale(identifier: "en_US")
        // From 995,000 two significant digits would print "1,000,000".
        if count >= 995_000 {
            return "\((count / 1_000_000).formatted(.number.precision(.fractionLength(0...1)).locale(english))) million"
        }
        if count >= 100 {
            return count.formatted(.number.precision(.significantDigits(2)).locale(english))
        }
        if count >= 10 { return count.rounded().formatted(.number.locale(english)) }
        return count.formatted(.number.precision(.fractionLength(0...1)).locale(english))
    }
}
