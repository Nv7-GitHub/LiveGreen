import Foundation

/// Lognormal peer distributions built from the profile and per-capita baselines (spec §9).
/// The leaderboard and percentiles compare whole yearly footprints: the region's people (`regionalDistribution`)
/// against your estimate (`estimate`), which is the per-capita figure × category shares × your profile
/// modifiers, with scanned items counted where they exceed it. `median(for:categories:)` gives a category
/// sub-footprint for people like you.
public struct CohortModel: Sendable {
    /// Metrics a scanned footprint keeps.
    public static let comparedMetrics: [MetricKey] = [.carbon, .water, .land, .yearlyElectricity]
    /// Metrics on the leaderboard and percentile cards: every metric with a per-capita baseline. Carbon is the
    /// whole footprint. Water, land and electricity count only the consumption categories' shares of the
    /// per-capita figure, because national withdrawals, farmland (one world average) and demand also cover
    /// industry, commerce and power-plant cooling that no profile places. Water and land come last so friends'
    /// carbon and electricity draws stay as they were.
    public static let leaderboardMetrics: [MetricKey] = [.carbon, .yearlyElectricity, .water, .land]

    public let profile: UserProfile
    public let baseline: PerCapitaBaseline
    public let reference: CohortReference

    public init(profile: UserProfile, baseline: PerCapitaBaseline, reference: CohortReference) {
        self.profile = profile
        self.baseline = baseline
        self.reference = reference
    }

    /// Nil when no baseline exists for the region (the bundled US baseline is the fallback).
    public init?(profile: UserProfile, store: ReferenceStore = .bundled) {
        guard let baseline = store.perCapita(for: profile.region) else { return nil }
        self.init(profile: profile, baseline: baseline, reference: store.cohort)
    }

    /// Profile multiplier on one category's share of the per-capita total for `metric`.
    public func modifier(for category: Category, metric: MetricKey = .carbon) -> Double {
        switch category {
        case .food:
            return baseline.dietModifiers[profile.diet] ?? 1
        case .clothing:
            return reference.clothingModifiers[profile.clothingHabit] ?? 1
        case .electronic, .household:
            // Shared appliances spread across the household: per-person use scales with size^(exponent − 1).
            var value = pow(Double(max(profile.householdSize, 1)), baseline.householdSizeExponent - 1)
            // Bigger homes run more appliances; electric heating adds to the electricity bill only.
            if metric == .carbon || metric == .yearlyElectricity {
                value *= reference.homeTypeModifiers[profile.homeType] ?? 1
            }
            if metric == .yearlyElectricity {
                value *= reference.heatingModifiers[profile.heating] ?? 1
            }
            return value
        case .packaging, .personalCare:
            return 1
        }
    }

    /// Peer median of the per-person yearly sub-footprint for `categories`.
    public func median(for metric: MetricKey, categories: Set<Category>) -> Double {
        guard let total = baseline.medians[metric] else { return 0 }
        let share = categories.reduce(0) { $0 + reference.share(of: $1, for: metric) * modifier(for: $1, metric: metric) }
        return total * share
    }

    /// Peer distribution of the sub-footprint; nil when the categories have no share of this metric.
    public func distribution(for metric: MetricKey, categories: Set<Category>) -> LogNormal? {
        let median = median(for: metric, categories: categories)
        guard median > 0, let sigma = baseline.sigmas[metric] else { return nil }
        return LogNormal(median: median, sigma: sigma)
    }

    /// Whole-footprint median (all categories), with the commute modifier applied to carbon: the
    /// distance-weighted mix of each mode's modifier (the main mode's when no distances are set).
    public func wholeFootprintMedian(for metric: MetricKey) -> Double {
        let base = baseline.medians[metric] ?? 0
        guard metric == .carbon else { return base }
        let distances = profile.commuteKmPerWeekByMode
        let total = distances.values.reduce(0, +)
        let modifier = total > 0
            ? distances.reduce(0) { $0 + (reference.commuteModifiers[$1.key] ?? 1) * $1.value } / total
            : reference.commuteModifiers[profile.commuteMode] ?? 1
        return base * modifier
    }

    /// Per-person yearly footprint of the region's people, before any profile adjustment: the whole carbon
    /// footprint, or the consumption categories' shares of per-capita water, land or electricity (home
    /// electricity is the electronics and household shares). Nil for metrics not on the leaderboard.
    public func regionalDistribution(for metric: MetricKey) -> LogNormal? {
        guard Self.leaderboardMetrics.contains(metric), let total = baseline.medians[metric],
              let sigma = baseline.sigmas[metric] else { return nil }
        let share = metric == .carbon ? 1 : Category.allCases.reduce(0) { $0 + reference.share(of: $1, for: metric) }
        guard total * share > 0 else { return nil }
        return LogNormal(median: total * share, sigma: sigma)
    }

    /// Your yearly footprint on the same basis as `regionalDistribution`. Each category counts the larger of
    /// two amounts: your profile's typical amount (per-capita × share × modifiers) or what you've scanned in
    /// it. Carbon adds your commute and the rest of the footprint (services, other goods), so with nothing
    /// scanned it equals `LifestyleEstimate.totalKg`.
    public func estimate(for metric: MetricKey, scanned: ScannedFootprint = .empty) -> Double? {
        guard Self.leaderboardMetrics.contains(metric), let total = baseline.medians[metric] else { return nil }
        let heating = reference.heatingModifiers[profile.heating] ?? 1
        var value = Category.allCases.reduce(0.0) { sum, category in
            var typical = total * reference.share(of: category, for: metric) * modifier(for: category, metric: metric)
            // As in `LifestyleEstimate`: the heating fuel shifts home-energy carbon too.
            if metric == .carbon, category == .electronic || category == .household { typical *= heating }
            return sum + max(typical, scanned.byCategory[category]?[metric] ?? 0)
        }
        if metric == .carbon {
            let shares = Category.allCases.reduce(0) { $0 + reference.share(of: $1, for: .carbon) }
            value += profile.commuteKmPerWeekByMode.reduce(0) { $0 + (LifestyleEstimate.kgPerKm[$1.key] ?? 0) * $1.value * 52 }
            value += max(0, total * (1 - shares - LifestyleEstimate.averageTravelShare))
        }
        return value
    }

    /// Compares your estimated footprint (profile plus scans) with the region's people for each leaderboard metric.
    public func compare(_ footprint: ScannedFootprint) -> [CohortComparison] {
        Self.leaderboardMetrics.compactMap { metric in
            guard let value = estimate(for: metric, scanned: footprint),
                  let distribution = regionalDistribution(for: metric) else { return nil }
            return CohortComparison(metric: metric, userValue: value, cohortMedian: distribution.median,
                                    greenerThan: Percentiles.greenerThan(value, in: distribution))
        }
    }
}

/// One metric's peer comparison.
public struct CohortComparison: Sendable, Hashable, Identifiable {
    public var metric: MetricKey
    /// The user's estimated yearly footprint (profile plus scans), canonical units.
    public var userValue: Double
    public var cohortMedian: Double
    /// Share of the region's people (0–1) with a larger footprint: "You're greener than 68% of people like you."
    public var greenerThan: Double

    public var id: MetricKey { metric }
    public var greenerThanPercent: Int { Int((greenerThan * 100).rounded()) }
}
