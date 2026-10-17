import Foundation
import GreenCore

/// Deterministic peer cohort (spec §9): for each cohort metric a lognormal distribution whose median is the
/// regional per-capita baseline, adjusted by diet and household size, and scoped to the scanned categories.
struct LocalCohortModel: CohortComparing {
    let baseline: PerCapitaBaseline?
    private let distributions: [MetricKey: LognormalDistribution]

    /// Fixed so every launch shows the same simulated network.
    static let networkSeed: UInt64 = 0x4C69_7665_4772_6565

    /// - Parameter scope: categories the user's footprint covers per metric; a metric with no scope has no
    ///   distribution, since there is nothing comparable to measure.
    init(profile: UserProfile, reference: any ReferenceProviding, scope: [MetricKey: Set<GreenCore.Category>]) {
        let baseline = Self.baseline(for: profile.region, in: reference)
        self.baseline = baseline
        var distributions: [MetricKey: LognormalDistribution] = [:]
        if let baseline {
            for metric in CohortMetric.all {
                guard let median = baseline.medians[metric], let sigma = baseline.sigmas[metric] else { continue }
                let share = CategoryScope.share(of: scope[metric] ?? [], for: metric)
                guard share > 0 else { continue }
                let adjusted = median * Self.modifier(for: metric, profile: profile, baseline: baseline) * share
                distributions[metric] = LognormalDistribution(median: adjusted, sigma: sigma)
            }
        }
        self.distributions = distributions
    }

    func distribution(for metric: MetricKey) -> LognormalDistribution? { distributions[metric] }

    func percentile(for metric: MetricKey, value: Double) -> Double {
        distributions[metric]?.cdf(value) ?? 0.5
    }

    func friends() -> [CohortFriend] {
        var generator = SeededGenerator(seed: Self.networkSeed)
        return Self.network.enumerated().map { index, member in
            // A shared "lifestyle" draw keeps each friend consistently greener or heavier across metrics.
            let lifestyle = generator.nextGaussian()
            var footprints: [MetricKey: Double] = [:]
            for metric in CohortMetric.all {
                let z = 0.7 * lifestyle + 0.71 * generator.nextGaussian()
                if let distribution = distributions[metric] { footprints[metric] = distribution.value(atZ: z) }
            }
            return CohortFriend(id: index, name: member.name, avatarSymbol: member.symbol, footprints: footprints)
        }
    }

    private static let network: [(name: String, symbol: String)] = [
        ("Maya", "leaf.fill"), ("Jonah", "bicycle"), ("Priya", "sun.max.fill"), ("Leo", "drop.fill"),
        ("Amara", "tree.fill"), ("Kenji", "tortoise.fill"), ("Sofia", "hare.fill"), ("Diego", "mountain.2.fill"),
    ]

    /// Most specific baseline first: US state, then country, then the world average.
    private static func baseline(for region: Region, in reference: any ReferenceProviding) -> PerCapitaBaseline? {
        [region.usState, region.countryCode, "WORLD"]
            .compactMap { $0 }
            .lazy
            .compactMap { reference.perCapita(region: $0) }
            .first
    }

    private static func modifier(for metric: MetricKey, profile: UserProfile, baseline: PerCapitaBaseline) -> Double {
        let household = pow(Double(max(profile.householdSize, 1)), baseline.householdSizeExponent - 1)
        let diet = metric == .yearlyElectricity ? 1 : (baseline.dietModifiers[profile.diet] ?? 1)
        return household * diet
    }
}
