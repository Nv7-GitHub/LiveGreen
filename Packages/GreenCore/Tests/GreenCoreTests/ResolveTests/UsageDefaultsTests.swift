import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// How often consumables are had (K1, Q3): typical weeks instead of identify's guesses, containers that follow their
/// food, answers that reach items of the same kind, and rates remembered across scans.
@Suite("Typical weeks and linked usage")
struct UsageDefaultsTests {
    private func pipeline(_ components: [IdentifiedComponent], remembered: [String: Double] = [:]) -> ScanPipeline {
        let store = ReferenceStore.bundled
        let products = FakeProductDatabase()
        let resolvers: [any MetricResolver] = [OpenFoodFactsResolver(products: products), FactorModelResolver(store: store),
                                               EstimateResolver()]
        var pipeline = ScanPipeline(vision: ScriptedVision(components: components), alternatives: FakeAlternativeSuggester(),
                                    products: products, ladder: EvidenceLadder(resolvers: resolvers),
                                    engine: ImpactEngine(reference: store), profile: .default)
        pipeline.rememberedUsage = remembered
        return pipeline
    }

    private static let scanID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    private static func est(_ value: Double) -> [MetricKey: EstimateRange] {
        [.carbon: EstimateRange(value: value, low: value / 2, high: value * 2)]
    }

    private static func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: width, height: height)
    }

    private static func latte(_ servings: Double, box: NormalizedRect = box(0.1, 0.1, 0.3, 0.5)) -> IdentifiedComponent {
        IdentifiedComponent(name: "Iced latte", category: .food, boundingBox: box,
                            quantities: Quantities(volumeLiters: 0.45, foodGroup: "latte"),
                            defaultUsage: UsageProfile(servingsPerWeek: servings), estimates: est(0.8))
    }

    private static func cup(_ uses: Double, box: NormalizedRect) -> IdentifiedComponent {
        IdentifiedComponent(name: "Clear plastic cup", category: .packaging, boundingBox: box,
                            identifiers: Identifiers(materials: [MaterialShare(material: "pet_thermoform", percent: 100)]),
                            quantities: Quantities(massKg: 0.014, packagingMassG: 14),
                            defaultUsage: UsageProfile(usesPerWeek: uses), estimates: est(0.05))
    }

    private static func chips(_ servings: Double) -> IdentifiedComponent {
        IdentifiedComponent(name: "Potato chips", category: .food, boundingBox: box(0.6, 0.6, 0.3, 0.3),
                            quantities: Quantities(servingKg: 0.028, foodGroup: "potato_crisps"),
                            defaultUsage: UsageProfile(servingsPerWeek: servings), estimates: est(0.1))
    }

    /// The same photo gave 1 or 2 drinks a week and 1 or 4 cups across runs, so its year moved up to 14×.
    @Test func theSamePhotoGivesTheSameYearWhateverIdentifyGuessed() async throws {
        let apart = Self.box(0.6, 0.05, 0.2, 0.3)
        let first = try await pipeline([Self.latte(1), Self.cup(4, box: apart), Self.chips(2)])
            .run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        let second = try await pipeline([Self.latte(4), Self.cup(1, box: apart), Self.chips(5)])
            .run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        #expect(first.yearlyTotals == second.yearlyTotals)
        #expect(first.components.map(\.usage) == second.components.map(\.usage))
        let latte = try #require(first.components.first { $0.name == "Iced latte" })
        #expect(latte.usage?.servingsPerWeek == UsageDefaults.servingsByGroup["latte"])
        #expect(latte.usage?.source == .typical)
        let cup = try #require(first.components.first { $0.category == .packaging })
        #expect(cup.parentID == nil)
        #expect(cup.usage?.usesPerWeek == 3)
        #expect(first.components.first { $0.name == "Potato chips" }?.usage?.servingsPerWeek == 2)
    }

    /// 17: one stain-remover spray read 0.02 or 0.3 bottles a year across runs; its weekly uses are a typical rate too.
    @Test func aHouseholdConsumableGetsATypicalWeekToo() async throws {
        func spray(_ uses: Double) -> IdentifiedComponent {
            var quantities = Quantities(massKg: 0.7, packagingMassG: 60)
            quantities.consumable = true
            quantities.usesPerContainer = 80
            return IdentifiedComponent(name: "Stain remover spray", category: .household, boundingBox: Self.box(0.2, 0.2, 0.3, 0.6),
                                       identifiers: Identifiers(materials: [MaterialShare(material: "detergent_formula", percent: 90),
                                                                            MaterialShare(material: "hdpe", percent: 10)]),
                                       quantities: quantities, defaultUsage: UsageProfile(usesPerWeek: uses), estimates: Self.est(0.5))
        }
        let first = try await pipeline([spray(1)]).run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        let second = try await pipeline([spray(14)]).run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        #expect(first.yearlyTotals == second.yearlyTotals)
        #expect(first.components.first?.usage?.usesPerWeek == UsageDefaults.householdConsumableUsesPerWeek)
        #expect(first.components.first?.usage?.source == .typical)
    }

    /// A drink's frequency never reached its cup or straw, though the question said "the drink and its cup".
    @Test func aDrinksCupAndStrawFollowTheDrink() async throws {
        let drinkBox = Self.box(0.1, 0.1, 0.3, 0.5)
        let straw = IdentifiedComponent(name: "Plastic straw", category: .packaging, boundingBox: Self.box(0.2, 0.05, 0.04, 0.3),
                                        identifiers: Identifiers(materials: [MaterialShare(material: "pp", percent: 100)]),
                                        quantities: Quantities(massKg: 0.001, packagingMassG: 1),
                                        defaultUsage: UsageProfile(usesPerWeek: 1), estimates: Self.est(0.004))
        let pipeline = pipeline([Self.latte(2, box: drinkBox), Self.cup(5, box: Self.box(0.08, 0.12, 0.32, 0.5)), straw])
        let scan = try await pipeline.run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        let drink = try #require(scan.components.first { $0.category == .food })
        let containers = scan.components.filter { $0.category == .packaging }
        #expect(containers.count == 2)
        #expect(containers.allSatisfy { $0.parentID == drink.id })
        #expect(containers.allSatisfy { $0.usage?.usesPerWeek == drink.usage?.servingsPerWeek })
        #expect(ScanPipeline.usageLinkedItems(of: drink, in: scan.components, reference: ReferenceStore.bundled).count == 2)
        // Changing the cup's rate changes its drink and the straw too.
        let cup = try #require(containers.first { $0.name.contains("cup") })
        #expect(Set(ScanPipeline.usageLinkedItems(of: cup, in: scan.components, reference: ReferenceStore.bundled).map(\.name))
                == ["Iced latte", "Plastic straw"])

        // An answer for the drink reaches its cup and straw...
        let daily = pipeline.applying([(drink.id, AnswerOption(label: "Daily", field: .servingsPerWeek, value: 7))], to: scan)
        #expect(daily.components.filter { $0.category == .packaging }.allSatisfy { $0.usage?.usesPerWeek == 7 })
        #expect(daily.component(withID: drink.id)?.usage?.source == .answered)
        // ...and one for the cup is one for its drink, so the straw follows too.
        let weekly = pipeline.applying([(cup.id, AnswerOption(label: "Weekly", field: .usesPerWeek, value: 1))], to: daily)
        #expect(weekly.component(withID: drink.id)?.usage?.servingsPerWeek == 1)
        #expect(weekly.components.filter { $0.category == .packaging }.allSatisfy { $0.usage?.usesPerWeek == 1 })
        let dailyCarbon = try #require(daily.yearlyTotals[.carbon]).value
        #expect(try #require(weekly.yearlyTotals[.carbon]).value < dailyCarbon / 5)
    }

    /// "How often do you eat ice cream like this?" changed 1 of 6 flavours.
    @Test func anAnswerReachesEveryItemOfItsKind() async throws {
        let pints = ["Vanilla", "Chocolate", "Cookie dough"].enumerated().map { index, flavour in
            IdentifiedComponent(name: "\(flavour) ice cream pint", category: .food,
                                boundingBox: Self.box(0.05 + Double(index) * 0.3, 0.2, 0.25, 0.3),
                                quantities: Quantities(servingKg: 0.11, foodGroup: "ice_cream"),
                                defaultUsage: UsageProfile(servingsPerWeek: 1), estimates: Self.est(0.5))
        }
        let pipeline = pipeline(pints + [Self.chips(2)])
        let scan = try await pipeline.run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        let vanilla = try #require(scan.components.first)
        let answered = pipeline.applying([(vanilla.id, AnswerOption(label: "Rarely", field: .servingsPerWeek, value: 0.25))], to: scan)
        let iceCream = answered.components.filter { $0.name.contains("ice cream") }
        #expect(iceCream.count == 3)
        #expect(iceCream.allSatisfy { $0.usage?.servingsPerWeek == 0.25 && $0.usage?.source == .answered })
        #expect(answered.components.first { $0.name == "Potato chips" }?.usage == scan.components.first { $0.name == "Potato chips" }?.usage)
    }

    /// Items of one kind may be on different bases: the same servings a week become packs for a per-pack one.
    @Test func aRateReachesAPerPackItemAsPacks() throws {
        var bowl = Component(name: "Ice cream", category: .food, quantities: Quantities(servingKg: 0.1, foodGroup: "ice_cream"),
                             usage: UsageProfile(servingsPerWeek: 1, source: .typical))
        bowl.metrics[.carbon] = .exact(0.45, unit: .kgCO2e, tier: .factorModel)
        var tub = Component(name: "Ice cream tub", category: .food, identifiers: Identifiers(gtin: "0000000000017"),
                            quantities: Quantities(servingKg: 0.1, foodGroup: "ice_cream", packNetKg: 0.5),
                            usage: UsageProfile(servingsPerWeek: 1, source: .typical))
        tub.metrics[.carbon] = .exact(2.2, unit: .kgCO2e, tier: .exactRecord)
        let scan = ScanResult(title: "Freezer", components: [bowl, tub])
        let answered = pipeline([]).applying([(bowl.id, AnswerOption(label: "2", field: .servingsPerWeek, value: 2))], to: scan)
        let tubAfter = try #require(answered.component(withID: tub.id))
        #expect(abs(FoodServing.packsPerWeek(of: tubAfter) - 0.4) < 1e-9)
        // Remembered in servings, so a later per-serving scan of the same food reads alike.
        #expect(abs((UsageDefaults.perWeek(of: tubAfter) ?? 0) - 2) < 1e-9)
    }

    @Test func rememberedAnswersStartLaterScans() async throws {
        let key = try #require(UsageDefaults.kindKey(for: Self.latte(1).makeComponent(), reference: ReferenceStore.bundled))
        #expect(key == "food:latte")
        let scan = try await pipeline([Self.latte(1), Self.chips(1)], remembered: [key: 6])
            .run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        let latte = try #require(scan.components.first { $0.name == "Iced latte" })
        #expect(latte.usage?.servingsPerWeek == 6)
        #expect(latte.usage?.source == .remembered)
        // Already the user's rate, so LiveGreen does not ask how often again.
        #expect(!latte.questions.contains { $0.id == QuestionGate.frequencyQuestionID })
        let chips = try #require(scan.components.first { $0.name == "Potato chips" })
        #expect(chips.usage?.source == .typical)
        #expect(chips.questions.contains { $0.id == QuestionGate.frequencyQuestionID })
    }

    /// The typical week is an assumption, so the results can ask about it even when the ranges are narrow.
    @Test func theAssumedRateCanBeAnsweredFromTheResults() async throws {
        let pipeline = pipeline([Self.chips(4)])
        let scan = try await pipeline.run(id: Self.scanID, image: Data([1]), hints: .none, mode: .photo)
        let pending = QuestionGate.pendingQuestions(for: scan.components)
        let question = try #require(pending.first)
        #expect(question.question.id == QuestionGate.frequencyQuestionID)
        #expect(question.currentValue == 2)
        let option = try #require(question.question.options.last)
        var answered = pipeline.applying([(question.componentID, option)], to: scan)
        answered.components = QuestionGate.settling(pending, in: answered.components)
        #expect(answered.components.first?.usage?.servingsPerWeek == 7)
        #expect(QuestionGate.pendingQuestions(for: answered.components).isEmpty)
    }

    @Test func scansSavedBeforeTheseFieldsStillLoad() throws {
        var component = Component(name: "Iced latte", category: .food, usage: UsageProfile(servingsPerWeek: 2))
        component.parentID = UUID()
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(component)) as? [String: Any])
        json["parentID"] = nil
        json["detailAnswer"] = nil
        var usage = try #require(json["usage"] as? [String: Any])
        usage["source"] = nil
        json["usage"] = usage
        let decoded = try JSONDecoder().decode(Component.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.parentID == nil)
        #expect(decoded.detailAnswer == nil)
        #expect(decoded.usage == UsageProfile(servingsPerWeek: 2))
    }
}

private struct ScriptedVision: VisionIdentifier {
    var components: [IdentifiedComponent]

    func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        IdentifyResponse(components: components, sceneTitle: "Test")
    }
}
