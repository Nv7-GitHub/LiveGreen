import Foundation

/// Lognormal peer distributions built from the profile and per-capita baselines (spec §9).
/// Comparisons are of category sub-footprints: the peer median for a set of categories is the per-capita
/// median × those categories' shares, adjusted by diet, clothing habit, household size, home type and heating.
public struct CohortModel: Sendable {
    public static let comparedMetrics: [MetricKey] = [.carbon, .water, .land, .yearlyElectricity]

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

    /// Compares a scanned footprint with peers for every metric it covers.
    public func compare(_ footprint: ScannedFootprint) -> [CohortComparison] {
        Self.comparedMetrics.compactMap { metric in
            guard let value = footprint.yearly[metric],
                  let distribution = distribution(for: metric, categories: footprint.categories(for: metric)) else { return nil }
            return CohortComparison(metric: metric, userValue: value, cohortMedian: distribution.median,
                                    greenerThan: Percentiles.greenerThan(value, in: distribution))
        }
    }
}

/// One metric's peer comparison.
public struct CohortComparison: Sendable, Hashable, Identifiable {
    public var metric: MetricKey
    /// The user's yearly sub-footprint, canonical units.
    public var userValue: Double
    public var cohortMedian: Double
    /// Share of peers (0–1) with a larger footprint: "You're greener than 68% of people like you."
    public var greenerThan: Double

    public var id: MetricKey { metric }
    public var greenerThanPercent: Int { Int((greenerThan * 100).rounded()) }
}
