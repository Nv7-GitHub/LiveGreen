import Foundation

extension ScanPipeline {
    /// Asks for greener alternatives and resolves them through the same ladder and engine as the
    /// originals (spec §7), then keeps only swaps without a big trade-off on any metric, best GreenScore
    /// first; deferrable loads also get the local smart-plug alternative. Items the suggester skipped, and the
    /// biggest item when none of its swaps was kept, get one more try with a note on what was wrong (S10).
    public func suggestAlternatives(for result: ScanResult) async throws -> ScanResult {
        let suggestions = try await alternatives.suggestAlternatives(for: result.components, profile: profile)
        var updated = result
        var notes: [UUID: String] = [:]
        for suggestion in suggestions {
            guard let index = updated.components.firstIndex(where: { $0.id == suggestion.componentID }) else { continue }
            let review = await reviewed(suggestion.alternatives, replacing: updated.components[index])
            updated.components[index].alternatives = review.kept
            notes[suggestion.componentID] = review.turnedDown
        }
        let retry = retryTargets(in: updated, answered: Set(suggestions.map(\.componentID)))
        if !retry.isEmpty {
            let retryNotes = Dictionary(uniqueKeysWithValues: retry.map { component in
                (component.id, notes[component.id].flatMap(\.trimmedNonEmpty).map { "Turned down: \($0)." }
                    ?? "No swap came back for this item.")
            })
            let more = (try? await alternatives.suggestAlternatives(for: retry, profile: profile, retrying: retryNotes)) ?? []
            for suggestion in more where retryNotes[suggestion.componentID] != nil {
                guard let index = updated.components.firstIndex(where: { $0.id == suggestion.componentID }) else { continue }
                let review = await reviewed(suggestion.alternatives, replacing: updated.components[index])
                if !review.kept.isEmpty { updated.components[index].alternatives = review.kept }
            }
        }
        for index in updated.components.indices where updated.components[index].plugCandidate != nil {
            let component = updated.components[index]
            if !component.alternatives.contains(where: { $0.kind == .smartPlugScheduling }) {
                updated.components[index].alternatives.append(.smartPlugScheduling(for: component))
            }
        }
        return updated
    }

    /// At most this many items get the second try, biggest yearly carbon first, so it stays one quick call.
    static let maxRetries = 4

    /// Suggested swaps made fit to show (S11): names and rationales tidied (`SwapText`), repeats and second-hand safety
    /// gear dropped, each resolved like the original (`resolve`), its rationale checked against its own comparison,
    /// then ranked by GreenScore with trade-offs dropped. `turnedDown` says why each dropped swap went, for a retry.
    func reviewed(_ suggested: [Alternative], replacing original: Component) async -> (kept: [Alternative], turnedDown: String) {
        var reasons: [String] = []
        var names = Set<String>()
        var resolved: [Alternative] = []
        for alternative in suggested where alternative.kind == .product {
            var swap = alternative
            swap.name = SwapText.name(alternative.name)
            swap.rationale = SwapText.rationale(alternative.rationale)
            guard names.insert(swap.name.lowercased()).inserted else { continue }
            if swap.isUnsafeSecondHand(replacing: original) {
                reasons.append("“\(swap.name)” (second-hand or kept-longer safety gear is never suggested)")
                continue
            }
            var done = await resolve(swap.onBasis(of: original), replacing: original)
            done.rationale = SwapText.rationale(done.rationale, checkedAgainst: original, alternative: done, engine: engine)
            resolved.append(done)
        }
        let kept = GreenScore.ranked(resolved, replacing: original, engine: engine)
        for swap in resolved where !kept.contains(where: { $0.id == swap.id }) {
            reasons.append("“\(swap.name)” (\(Self.rejection(GreenScore.assess(swap, replacing: original, engine: engine))))")
        }
        return (kept, reasons.joined(separator: "; "))
    }

    /// Why GreenScore turned a swap down, in words the suggester can act on.
    static func rejection(_ assessment: GreenScore.Assessment) -> String {
        if assessment.isRelabelledFood { return "the same food under another name" }
        let limit = -log(1 + GreenScore.maxWorsening)
        if let worst = assessment.changes.filter({ !GreenScore.vetoExempt.contains($0.key) && $0.value < limit })
            .min(by: { $0.value < $1.value })?.key {
            return "\(SwapText.phrase(worst)) clearly worse"
        }
        return assessment.changes.isEmpty ? "nothing to compare it on" : "too small a gain overall"
    }

    /// Who gets a second try: items the suggester left out, and the biggest yearly-carbon item when it has no product
    /// swap left, at most `maxRetries`, biggest first.
    func retryTargets(in result: ScanResult, answered: Set<UUID>) -> [Component] {
        let byCarbon = result.components.enumerated().sorted { lhs, rhs in
            let (a, b) = (yearlyCarbon(lhs.element), yearlyCarbon(rhs.element))
            return a != b ? a > b : lhs.offset < rhs.offset
        }.map(\.element)
        let top = byCarbon.first?.id
        let targets = byCarbon.filter { component in
            !component.alternatives.contains { $0.kind == .product } && (!answered.contains(component.id) || component.id == top)
        }
        return Array(targets.prefix(Self.maxRetries))
    }

    private func yearlyCarbon(_ component: Component) -> Double {
        (component.metrics[.carbon]?.value ?? 0) * GreenScore.yearlyFactor(.carbon, for: component, engine: engine)
    }

    /// One swap resolved on the same footing as the item it replaces: filed as household when reusable, kept over the
    /// original's lifespan unless it is meant to last a different time, resolved like an original (`resolveAlternative`),
    /// then given washing for each use (reusables) or its second-hand share of production impacts. A food swap that
    /// does not say whether it is cooked is prepared like the original (lentil pilaf for barley pilaf), so a cooked
    /// portion is never compared with a dry one.
    func resolve(_ alternative: Alternative, replacing original: Component) async -> Alternative {
        var swap = alternative
        swap.category = Alternative.scoredCategory(alternative.category, isReusable: alternative.isReusable)
        if swap.category == .food, swap.quantities.cooked == nil {
            swap.quantities.cooked = FoodServing.isCooked(original, reference: engine.reference)
        }
        var component = Component(id: swap.id, name: swap.name, category: swap.category, identifiers: swap.identifiers,
                                  quantities: swap.quantities, usage: swap.usage ?? original.usage,
                                  fallbackEstimates: swap.fallbackEstimates)
        if let lifespan = comparedLifespan(of: swap, replacing: original) { component.metrics[.lifespan] = lifespan }
        var resolved = completed(await resolveAlternative(component, condition: swap.condition), deferrable: nil)
        if swap.isReusable, resolved.category == .household {
            let uses = resolved.usage?.usesPerWeek ?? original.usage?.usesPerWeek ?? 1
            resolved = engine.addingWashing(usesPerWeek: uses, to: resolved, profile: profile)
        }
        if let share = swap.condition.productionShare {
            resolved = engine.secondHand(resolved, share: share, profile: profile)
        }
        swap.metrics = resolved.metrics
        return swap
    }

    /// The lifespan a durable swap is resolved and annualized with, set before the ladder runs so carbon's use phase
    /// and the per-year view both use it. A stated `lifespanYears` wins (a laptop kept longer, a reusable's life),
    /// except for a second-hand item, which lasts no longer than a new one. A swap of the same kind as the original
    /// (same category, no other device type) otherwise takes the original's lifespan, so a used SUV is not "greener"
    /// only because the suggester guessed it lasts 10 years against the original's 5. Nil leaves it to the ladder.
    func comparedLifespan(of swap: Alternative, replacing original: Component) -> Measured? {
        let replacement = swap.asComponent(replacing: original)
        guard GreenScore.isDurable(replacement, engine: engine) else { return nil }
        if swap.condition == .new, let years = swap.lifespanYears, years > 0 {
            return Measured(value: years, relativeRange: 0.3, unit: .years, tier: .estimate,
                            sources: [Source(title: "Years the swap is kept, as suggested", tier: .estimate)])
        }
        let sameKind = swap.category == original.category
            && Self.sameDeviceType(swap.quantities.deviceType, original.quantities.deviceType)
        guard sameKind, GreenScore.isDurable(original, engine: engine) else { return nil }
        return engine.lifespan(of: original)
    }

    /// Device types match when equal or when either side gives none.
    static func sameDeviceType(_ a: String?, _ b: String?) -> Bool {
        guard let a = a?.trimmedNonEmpty?.lowercased(), let b = b?.trimmedNonEmpty?.lowercased() else { return true }
        return a == b
    }

    /// Records and cited research first, as for originals. A swap the factor tables can model (`isModelable`) then
    /// goes through the same factor model as the original, so the two are compared on one tier, and the suggester's
    /// estimates only fill gaps; otherwise the estimates come first, since the generic factors would only repeat the
    /// original's numbers.
    ///
    /// A device type's table gives the typical model's draw, which is exactly where an efficient model differs. So a
    /// new electronic swap is also modeled with its own power estimates, and that version is kept when it uses less
    /// electricity than the typical model. A second-hand swap, or one whose estimate draws more, keeps the table's
    /// draw like the original rather than whatever the estimate guessed.
    ///
    /// Swaps are neither read from nor written to the resolution cache: their mass and materials are the suggester's
    /// guesses, and a "used Honda CR-V" stored under `bm:honda|cr-v` would give a later scan of a real one its numbers.
    func resolveAlternative(_ component: Component, condition: Alternative.Condition = .new) async -> Component {
        var result = await ladder.resolve(component, profile: profile, tiers: .exactRecord ... .researchedSpec)
        guard Self.isModelable(component) else {
            result = await ladder.resolve(result, profile: profile, tiers: .estimate ... .estimate)
            return await ladder.resolve(result, profile: profile, tiers: .factorModel ... .estimate)
        }
        let modeled = await ladder.resolve(result, profile: profile, tiers: .factorModel ... .estimate)
        let power = Set([MetricKey.powerOn, .standbyPower]).intersection(result.missingMetrics)
        guard component.category == .electronic, condition == .new, !power.isEmpty,
              let estimated = try? await EstimateResolver().resolve(ResolutionRequest(component: result, metrics: power,
                                                                                      profile: profile)),
              !estimated.metrics.isEmpty else { return modeled }
        result.metrics.merge(estimated.metrics) { current, _ in current }
        let efficient = await ladder.resolve(result, profile: profile, tiers: .factorModel ... .estimate)
        guard let ownKWh = efficient.metrics[.yearlyElectricity]?.value,
              let typicalKWh = modeled.metrics[.yearlyElectricity]?.value, ownKWh < typicalKWh else { return modeled }
        return efficient
    }

    /// Whether the factor tables can model the swap from what the suggester gave: a food group for food, a device
    /// type for electronics, materials with a mass for everything else.
    static func isModelable(_ component: Component) -> Bool {
        let q = component.quantities
        let hasMaterials = !component.identifiers.materials.isEmpty
        switch component.category {
        case .food: return q.foodGroup?.trimmedNonEmpty != nil
        case .electronic: return q.deviceType?.trimmedNonEmpty != nil
        case .clothing, .household: return hasMaterials && (q.massKg ?? 0) > 0
        case .packaging: return hasMaterials && ((q.packagingMassG ?? 0) > 0 || (q.massKg ?? 0) > 0)
        case .personalCare: return hasMaterials && (q.packagingMassG ?? 0) > 0
        case .vehicle: return true
        }
    }
}
