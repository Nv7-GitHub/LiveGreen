import Foundation
import GreenCore

/// Suggests one deterministic greener alternative per component, with estimates 40% better
/// than the component's own fallback estimates.
public struct FakeAlternativeSuggester: AlternativeSuggester {
    public var latency: Duration

    public init(latency: Duration = .zero) {
        self.latency = latency
    }

    public func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion] {
        try await simulateLatency(latency)
        return components.map { component in
            AlternativeSuggestion(componentID: component.id, alternatives: [alternative(for: component)])
        }
    }

    private func alternative(for component: Component) -> Alternative {
        let (name, rationale, practicality) = Self.swap(for: component)
        var estimates: [MetricKey: EstimateRange] = [:]
        for (metric, estimate) in component.fallbackEstimates {
            let factor = metric.higherIsBetter ? 1.3 : 0.6
            let bound = metric == .recyclablePercent ? 100.0 : .infinity
            estimates[metric] = EstimateRange(value: min(estimate.value * factor, bound),
                                              low: min(estimate.low * factor, bound),
                                              high: min(estimate.high * factor, bound))
        }
        return Alternative(name: name, category: component.category, quantities: component.quantities,
                           usage: component.usage, rationale: rationale, practicality: practicality,
                           fallbackEstimates: estimates)
    }

    private static func swap(for component: Component) -> (String, String, Practicality) {
        switch component.category {
        case .electronic:
            ("Refurbished \(component.name.lowercased())",
             "Refurbished devices avoid most manufacturing emissions.", Practicality(cost: .lower, effort: .easy))
        case .food:
            ("Plant-based \(component.name.lowercased())",
             "Plant proteins need far less land and emit less methane.", Practicality(cost: .similar, effort: .easy))
        case .packaging:
            ("Reusable steel cup", "One cup replaces hundreds of disposables.", Practicality(cost: .higher, effort: .easy))
        case .clothing:
            ("Second-hand \(component.name.lowercased())",
             "Buying used avoids new fiber production.", Practicality(cost: .lower, effort: .moderate))
        case .household, .personalCare:
            ("Refillable \(component.name.lowercased())",
             "Refills cut packaging and transport.", Practicality(cost: .similar, effort: .moderate))
        }
    }
}
