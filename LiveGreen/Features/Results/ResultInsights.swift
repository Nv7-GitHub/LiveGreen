import Foundation
import GreenCore

/// Derived figures for the results screen: per-component shares and evidence confidence.
nonisolated enum ResultInsights {
    /// Sum of one metric across components (values only).
    static func total(_ metric: MetricKey, in components: [Component]) -> Double {
        components.reduce(0) { $0 + max(0, $1.metrics[metric]?.value ?? 0) }
    }

    /// The component's share (0–1) of the scan's total for `metric`; 0 when unknown.
    static func share(of component: Component, metric: MetricKey, in components: [Component]) -> Double {
        let sum = total(metric, in: components)
        guard sum > 0, let value = component.metrics[metric]?.value else { return 0 }
        return max(0, value) / sum
    }

    /// Fraction of carbon per evidence tier, in tier order, omitting empty tiers.
    static func carbonShareByTier(_ components: [Component]) -> [(tier: Tier, share: Double)] {
        let sum = total(.carbon, in: components)
        guard sum > 0 else { return [] }
        return Tier.allCases.compactMap { tier in
            let part = components
                .compactMap { $0.metrics[.carbon] }
                .filter { $0.tier == tier }
                .reduce(0) { $0 + max(0, $1.value) }
            return part > 0 ? (tier, part / sum) : nil
        }
    }

    /// Confidence meter (spec §6): share of total carbon resolved at T1 or T2.
    static func confidence(_ components: [Component]) -> Double {
        carbonShareByTier(components)
            .filter { $0.tier <= .researchedSpec }
            .reduce(0) { $0 + $1.share }
    }

    /// Picker options for a scan: metrics at least one component's category uses and has a value for.
    /// "All" is offered when more than one metric is.
    static func availableFilters(for components: [Component]) -> [ResultMetricFilter] {
        let metrics = ResultMetricFilter.allCases.filter { filter in
            guard let metric = filter.metric else { return false }
            return components.contains { $0.category.applies(metric) && $0.metrics[metric] != nil }
        }
        return metrics.count > 1 ? metrics + [.all] : metrics
    }

    /// Components that report `filter`'s metric ("All" keeps every component).
    static func components(_ components: [Component], showing filter: ResultMetricFilter) -> [Component] {
        guard let metric = filter.metric else { return components }
        return components.filter { $0.category.applies(metric) && $0.metrics[metric] != nil }
    }

    /// Components ordered by the given metric, largest first; unknown values last.
    static func ranked(_ components: [Component], by metric: MetricKey) -> [Component] {
        components.sorted { lhs, rhs in
            let l = lhs.metrics[metric]?.value ?? -.infinity
            let r = rhs.metrics[metric]?.value ?? -.infinity
            return metric.higherIsBetter ? l < r : l > r
        }
    }
}
