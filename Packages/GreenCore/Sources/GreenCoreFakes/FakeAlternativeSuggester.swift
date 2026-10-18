import Foundation
import GreenCore

/// Suggests one deterministic greener alternative per component. Disposable packaging gets a reusable steel one,
/// modeled from its own mass and material like a real suggester's. Everything else gets estimates 40% better than
/// the component's resolved metrics (its own fallback estimates where a metric is unresolved) and names no food
/// group, device type or materials, so the pipeline uses the estimates rather than modeling the swap as the same
/// item; a durable swap of the same kind is still compared over the original's lifespan. Every swap passes the
/// GreenScore trade-off rule.
public struct FakeAlternativeSuggester: AlternativeSuggester {
    public var latency: Duration

    public init(latency: Duration = .zero) {
        self.latency = latency
    }

    public func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion] {
        try await simulateLatency(latency)
        // Per serving like the real suggesters' estimates; the pipeline scales swaps for a per-pack item to its pack.
        return components.map(FoodServing.servingView).map { component in
            AlternativeSuggestion(componentID: component.id, alternatives: [alternative(for: component)])
        }
    }

    private func alternative(for component: Component) -> Alternative {
        let (name, rationale, practicality) = Self.swap(for: component)
        if component.category == .packaging { return reusable(for: component, name: name, rationale: rationale,
                                                              practicality: practicality) }
        var baseline = component.fallbackEstimates
        for (metric, measured) in component.metrics {
            // An estimated swap's carbon is embodied only; the pipeline adds its use phase, as for originals.
            let share = metric == .carbon && component.category == .electronic
                ? 1 - (ImpactEngine().stageShares(for: component)[.use] ?? 0) : 1
            baseline[metric] = EstimateRange(value: measured.value * share, low: measured.low * share,
                                             high: measured.high * share)
        }
        var estimates: [MetricKey: EstimateRange] = [:]
        for (metric, estimate) in baseline {
            let factor = metric.higherIsBetter ? 1.3 : 0.6
            let bound = metric == .recyclablePercent ? 100.0 : .infinity
            estimates[metric] = EstimateRange(value: min(estimate.value * factor, bound),
                                              low: min(estimate.low * factor, bound),
                                              high: min(estimate.high * factor, bound))
        }
        var quantities = component.quantities
        quantities.foodGroup = nil
        quantities.deviceType = nil
        return Alternative(name: name, category: component.category, quantities: quantities,
                           usage: component.usage, rationale: rationale, practicality: practicality,
                           fallbackEstimates: estimates)
    }

    /// A steel cup or food container used for five years, washed after every use.
    private func reusable(for component: Component, name: String, rationale: String,
                          practicality: Practicality) -> Alternative {
        let massKg = name.lowercased().contains("container") ? 0.35 : 0.3
        return Alternative(name: name, category: .household,
                           identifiers: Identifiers(materials: [MaterialShare(material: "steel", percent: 100)]),
                           quantities: Quantities(massKg: massKg), usage: component.usage, rationale: rationale,
                           practicality: practicality,
                           fallbackEstimates: [.lifespan: EstimateRange(value: 5, low: 3, high: 8)],
                           isReusable: true, lifespanYears: 5)
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
            ("Reusable steel food container", "Bring your own container; one replaces hundreds of takeout boxes.",
             Practicality(cost: .higher, effort: .moderate))
        case .packaging:
            ("Reusable steel cup", "One cup replaces hundreds of disposables.", Practicality(cost: .higher, effort: .easy))
        case .clothing:
            ("Second-hand \(inline(component.name))",
             "Buying used avoids new fiber production.", Practicality(cost: .lower, effort: .moderate))
        case .household, .personalCare:
            ("Refillable \(inline(component.name))",
             "Refills cut packaging and transport.", Practicality(cost: .similar, effort: .moderate))
        case .vehicle:
            ("Used electric \(inline(component.name))",
             "Driving on electricity cuts tailpipe emissions; buying used avoids making a new car.",
             Practicality(cost: .similar, effort: .hard))
        }
    }
}
