import Foundation
import Synchronization
import Testing
@testable import GreenCore
import GreenCoreFakes

/// What the swaps screen is given to say (S10, S11 of the image QA): tidy names and rationales that match their
/// charts, no unsafe second-hand gear, honest cost tags, and a second try when the main item got nothing.
@Suite("Swap review")
struct SwapReviewTests {
    // MARK: Names

    @Test func namesDropSpecsExamplesAndRepeats() {
        #expect(SwapText.name("Refurbished business laptop (e.g., Lenovo ThinkPad T14), 14 in") == "Refurbished business laptop")
        #expect(SwapText.name("Refurbished laptop (Dell or ThinkPad), 14-15 in") == "Refurbished laptop (Dell or ThinkPad)")
        #expect(SwapText.name("Buy a used hybrid bicycle (second-hand)") == "Buy a used hybrid bicycle")
        #expect(SwapText.name("Nerds Gummy Clusters (one serving)") == "Nerds Gummy Clusters")
        #expect(SwapText.name("Concentrate refill, 22 fl oz") == "Concentrate refill")
        #expect(SwapText.name("  reusable   steel cup ") == "Reusable steel cup")
        #expect(SwapText.name("Home-blended smoothie (reusable cup)") == "Home-blended smoothie (reusable cup)",
                "an aside that says something stays")
        #expect(SwapText.name("Thrifted jacket (second-hand)") == "Thrifted jacket")
        #expect(SwapText.name("Jacket (second-hand)") == "Jacket (second-hand)", "the only place the condition is said")
    }

    // MARK: Rationales

    @Test func rationalesLoseModelTalkAndTheProfile() {
        #expect(SwapText.rationale("Not recommended to model precisely; a homemade vinaigrette with less oil cuts oil use while keeping the same role.")
            == "A homemade vinaigrette with less oil cuts oil use while keeping the same role.")
        #expect(SwapText.rationale("The user commutes by transit and drives about twice a week, so a car-share covers the rest.") == "")
        #expect(SwapText.rationale("Bamboo grows fast; it needs no pesticides") == "Bamboo grows fast. It needs no pesticides.")
        #expect(SwapText.rationale("Lighter, e.g. for travel. Lasts years.") == "Lighter, e.g. for travel. Lasts years.")
    }

    @Test func claimsAreReadNearTheirMetric() {
        typealias Claim = SwapText.Claim
        #expect(SwapText.claims(in: "Pulses emit a small fraction of beef's methane and need far less land.")
            == [Claim(metric: .carbon, direction: .better), Claim(metric: .land, direction: .better)])
        #expect(SwapText.claims(in: "Overnight oats have similar water and carbon to chia.")
            == [Claim(metric: .water, direction: .similar), Claim(metric: .carbon, direction: .similar)])
        #expect(SwapText.claims(in: "A more energy-efficient model.").isEmpty)
        #expect(SwapText.claims(in: "Made with more recycled plastic.").isEmpty)
        #expect(SwapText.claims(in: "A plastic-free wrap.") == [Claim(metric: .plasticMass, direction: .better)])
        #expect(SwapText.claims(in: "Less plastic, but more water.")
            == [Claim(metric: .plasticMass, direction: .better), Claim(metric: .water, direction: .worse)])
    }

    @Test func aRationaleTheChartContradictsIsReplaced() {
        // 24: "similar water and carbon" above charts saying 26% and 85% better.
        let chia = Component(name: "Chia pudding", category: .food,
                             metrics: [.carbon: .exact(1.0, unit: .kgCO2e, tier: .factorModel),
                                       .water: .exact(100, unit: .liters, tier: .factorModel)],
                             usage: UsageProfile(servingsPerWeek: 2))
        let oats = Alternative(name: "Overnight oats", category: .food, rationale: "",
                               metrics: [.carbon: .exact(0.74, unit: .kgCO2e, tier: .factorModel),
                                         .water: .exact(15, unit: .liters, tier: .factorModel)])
        let checked = SwapText.rationale("Oats have similar water and carbon to chia. They keep for days.",
                                         checkedAgainst: chia, alternative: oats)
        #expect(checked == "They keep for days.")
        #expect(SwapText.rationale("Oats have similar water and carbon to chia.", checkedAgainst: chia, alternative: oats)
            == "Better on carbon and water for the same job.")
        #expect(SwapText.rationale("Oats need far less water.", checkedAgainst: chia, alternative: oats)
            == "Oats need far less water.", "a claim the chart agrees with stays")
    }

    // MARK: Safety and cost

    @Test func secondHandSafetyGearIsNeverSuggested() {
        let helmet = Component(name: "Bicycle helmets", category: .clothing)
        let bike = Component(name: "Bicycle with child seat", category: .household)
        #expect(Alternative(name: "Second-hand or longer-kept helmet", category: .clothing, rationale: "")
            .isUnsafeSecondHand(replacing: helmet))
        #expect(Alternative(name: "Keep current helmet longer", category: .clothing, rationale: "")
            .isUnsafeSecondHand(replacing: helmet))
        #expect(Alternative(name: "Buy used", category: .clothing, rationale: "", condition: .used)
            .isUnsafeSecondHand(replacing: helmet))
        #expect(!Alternative(name: "Helmet with a recycled EPS liner", category: .clothing, rationale: "")
            .isUnsafeSecondHand(replacing: helmet))
        #expect(!Alternative(name: "Buy a used city bicycle", category: .household, rationale: "", condition: .used)
            .isUnsafeSecondHand(replacing: bike), "the seat is not part of the swap")
        #expect(Alternative(name: "Buy a used bicycle with child seat", category: .household, rationale: "", condition: .used)
            .isUnsafeSecondHand(replacing: bike))
        #expect(Alternative(name: "Pre-owned infant car seat", category: .household, rationale: "")
            .isUnsafeSecondHand(replacing: Component(name: "Car seat", category: .household)))
    }

    @Test func purchasesAndThePlugAreNotSavings() {
        let charger = Component(name: "E-bike charger", category: .electronic)
        let plug = Alternative.smartPlugScheduling(for: charger)
        #expect(plug.practicality.cost == .higher, "the plug is bought and saves no electricity")
        #expect(plug.isPurchase)
        #expect(Alternative(name: "Buy a used bicycle", category: .household, rationale: "", condition: .used).isPurchase)
        #expect(Alternative(name: "Refurbished laptop", category: .electronic, rationale: "", condition: .refurbished).isPurchase)
        #expect(!Alternative(name: "Keep it two more years", category: .electronic, rationale: "").isPurchase)
        #expect(!Alternative(name: "Car-share for occasional trips", category: .household, rationale: "").isPurchase)
    }

    @Test func thePromptKeepsTheProfileInTheBackgroundAndPassesRetryNotes() throws {
        let camera = Component(name: "Camera", category: .electronic)
        let first = try ClaudeClient.alternativesUserText(components: [camera], profile: .default)
        #expect(first.contains("User profile (app defaults the user has not confirmed; background only, do not mention it)"))
        #expect(!first.contains("Second try"))
        var onboarded = UserProfile.default
        onboarded.onboardingCompleted = true
        let retry = try ClaudeClient.alternativesUserText(components: [camera], profile: onboarded,
                                                          retrying: [camera.id: "Turned down: “Bigger camera” (carbon clearly worse)."])
        #expect(retry.contains("User profile (background only; do not mention it)"))
        #expect(retry.contains("Second try for these components."))
        #expect(retry.contains("- \(camera.id.uuidString): Turned down: “Bigger camera” (carbon clearly worse)."))
        #expect(retry.hasSuffix("Call `suggest_alternatives` with one entry per component id."))
        let system = ClaudeClient.alternativesSystemPrompt(vocabulary: ReferenceStore.bundled.vocabulary)
        #expect(system.contains("Never suggest second-hand, refurbished or kept-longer safety gear"))
        #expect(system.contains("Do not say how any metric compares"))
    }

    // MARK: In the pipeline

    private static let store = ReferenceStore.bundled

    /// Answers from a script: the first call's suggestions, then the retry's, recording what each call asked.
    private final class ScriptedSuggester: AlternativeSuggester, Sendable {
        typealias Script = @Sendable ([Component]) async -> [AlternativeSuggestion]
        let first: Script
        let retry: Script
        private let log = Mutex<[(ids: [UUID], notes: [UUID: String])]>([])

        init(first: @escaping Script, retry: @escaping Script) {
            self.first = first
            self.retry = retry
        }

        var calls: [(ids: [UUID], notes: [UUID: String])] { log.withLock { $0 } }

        func suggestAlternatives(for components: [Component], profile: UserProfile) async throws -> [AlternativeSuggestion] {
            log.withLock { $0.append((components.map(\.id), [:])) }
            return await first(components)
        }

        func suggestAlternatives(for components: [Component], profile: UserProfile,
                                 retrying notes: [UUID: String]) async throws -> [AlternativeSuggestion] {
            log.withLock { $0.append((components.map(\.id), notes)) }
            return await retry(components)
        }
    }

    /// The demo suggester's swaps, which pass the trade-off rule.
    private static let demoSwaps: ScriptedSuggester.Script = { components in
        (try? await FakeAlternativeSuggester().suggestAlternatives(for: components, profile: .default)) ?? []
    }

    private func pipeline(_ suggester: any AlternativeSuggester) -> ScanPipeline {
        ScanPipeline(vision: FakeVisionIdentifier(scene: .deskSetup), alternatives: suggester, products: FakeProductDatabase(),
                     ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: Self.store), EstimateResolver()]),
                     engine: ImpactEngine(reference: Self.store), profile: .default)
    }

    private func scan(_ pipeline: ScanPipeline) async throws -> ScanResult {
        try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
    }

    @Test func itemsTheSuggesterSkippedGetASecondTry() async throws {
        // 22: one of seven items got a swap; the prompt asks for every one.
        let suggester = ScriptedSuggester(first: { _ in [] }, retry: Self.demoSwaps)
        let pipeline = pipeline(suggester)
        let result = try await pipeline.suggestAlternatives(for: try await scan(pipeline))
        #expect(suggester.calls.count == 2)
        let retried = try #require(suggester.calls.last)
        #expect(retried.ids.count == min(result.components.count, ScanPipeline.maxRetries))
        #expect(retried.notes.values.allSatisfy { $0 == "No swap came back for this item." })
        for id in retried.ids {
            #expect(result.component(withID: id)?.alternatives.contains { $0.kind == .product } == true)
        }
    }

    @Test func theBiggestItemIsRetriedWithWhyItsSwapsWereTurnedDown() async throws {
        // 07: the camera was 92% of the carbon and had no swap and no explanation.
        let worse: ScriptedSuggester.Script = { components in
            components.map { component in
                var estimates = component.fallbackEstimates
                for (metric, measured) in component.metrics {
                    let factor = metric.higherIsBetter ? 0.2 : 5.0
                    estimates[metric] = EstimateRange(value: measured.value * factor, low: measured.low * factor,
                                                      high: measured.high * factor)
                }
                return AlternativeSuggestion(componentID: component.id, alternatives: [
                    Alternative(name: "Bigger \(component.name)", category: component.category, rationale: "",
                                fallbackEstimates: estimates),
                ])
            }
        }
        let suggester = ScriptedSuggester(first: worse, retry: { _ in [] })
        let pipeline = pipeline(suggester)
        let scan = try await scan(pipeline)
        let result = try await pipeline.suggestAlternatives(for: scan)
        #expect(suggester.calls.count == 2)
        let retried = try #require(suggester.calls.last)
        #expect(retried.ids.count == 1, "everything was answered, so only the biggest item is asked again")
        let note = try #require(retried.notes[retried.ids[0]])
        #expect(note.hasPrefix("Turned down: “Bigger "))
        #expect(note.contains("clearly worse"))
        #expect(result.components.allSatisfy { !$0.alternatives.contains { $0.kind == .product } })
    }

    @Test func noRetryWhenTheBiggestItemHasASwap() async throws {
        let suggester = ScriptedSuggester(first: Self.demoSwaps, retry: { _ in [] })
        let pipeline = pipeline(suggester)
        _ = try await pipeline.suggestAlternatives(for: try await scan(pipeline))
        #expect(suggester.calls.count == 1)
    }

    @Test func swapsAreTidiedDedupedAndSafe() async throws {
        let cup = Component(name: "PET cup", category: .packaging,
                            identifiers: Identifiers(materials: [MaterialShare(material: "pet", percent: 100)]),
                            quantities: Quantities(massKg: 0.012), usage: UsageProfile(usesPerWeek: 3))
        func jar(_ name: String, rationale: String) -> Alternative {
            Alternative(name: name, category: .household,
                        identifiers: Identifiers(materials: [MaterialShare(material: "glass", percent: 100)]),
                        quantities: Quantities(massKg: 0.25), rationale: rationale,
                        fallbackEstimates: [.lifespan: EstimateRange(value: 5, low: 3, high: 8)],
                        isReusable: true, lifespanYears: 5)
        }
        let swaps = [jar("Reusable glass jar (e.g. Weck), 500 ml", rationale: "LiveGreen modeled this from glass; you wash and reuse it."),
                     jar("Reusable glass jar", rationale: "Duplicate."),
                     Alternative(name: "Second-hand helmet", category: .clothing, rationale: "", condition: .used)]
        let pipeline = pipeline(ScriptedSuggester(first: { components in
            components.map { AlternativeSuggestion(componentID: $0.id, alternatives: swaps) }
        }, retry: { _ in [] }))
        let original = pipeline.completed(await pipeline.ladder.resolve(cup, profile: .default, tiers: EvidenceLadder.allTiers),
                                          deferrable: nil)
        let result = try await pipeline.suggestAlternatives(for: ScanResult(title: "Cup", components: [original]))
        let shown = try #require(result.components.first?.alternatives)
        #expect(shown.map(\.name) == ["Reusable glass jar"])
        #expect(shown[0].rationale == "You wash and reuse it.")
    }
}
