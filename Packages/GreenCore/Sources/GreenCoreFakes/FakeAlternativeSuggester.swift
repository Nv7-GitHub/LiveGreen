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

    /// Lowercases a leading common word so it reads mid-sentence, keeping brands and acronyms ("ASUS").
    private static func inline(_ name: String) -> String {
        let firstWord = name.prefix { !$0.isWhitespace }
        guard let first = firstWord.first, first.isUppercase,
              firstWord.dropFirst().allSatisfy({ !$0.isUppercase }) else { return name }
        return first.lowercased() + name.dropFirst()
    }

    /// "Beef burger" becomes "burger", so the swap reads "Plant-based burger".
    private static func withoutMeat(_ name: String) -> String {
        let meats: Set<String> = ["beef", "chicken", "pork", "lamb", "turkey", "bacon"]
        let words = name.split(separator: " ")
        let kept = words.filter { !meats.contains($0.lowercased()) }
        return kept.isEmpty ? name : kept.joined(separator: " ")
    }

    private static func swap(for component: Component) -> (String, String, Practicality) {
        switch component.category {
        case .electronic:
            ("Refurbished \(inline(component.name))",
             "Refurbished devices avoid most manufacturing emissions.", Practicality(cost: .lower, effort: .easy))
        case .food:
            ("Plant-based \(inline(withoutMeat(component.name)))",
             "Plant proteins need far less land and emit less methane.", Practicality(cost: .similar, effort: .easy))
        case .packaging where component.name.lowercased().contains("box"):
            ("Reusable food container", "Bring your own container; one replaces hundreds of takeout boxes.",
             Practicality(cost: .higher, effort: .moderate))
        case .packaging:
            ("Reusable steel cup", "One cup replaces hundreds of disposables.", Practicality(cost: .higher, effort: .easy))
        case .clothing:
            ("Second-hand \(inline(component.name))",
             "Buying used avoids new fiber production.", Practicality(cost: .lower, effort: .moderate))
        case .household, .personalCare:
            ("Refillable \(inline(component.name))",
             "Refills cut packaging and transport.", Practicality(cost: .similar, effort: .moderate))
        }
    }
}
