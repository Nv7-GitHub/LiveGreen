import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Detail questions for T4 items")
struct SpecQuestionTests {
    private func pipeline(_ components: [IdentifiedComponent] = []) -> ScanPipeline {
        let store = ReferenceStore.bundled
        let products = FakeProductDatabase()
        let resolvers: [any MetricResolver] = [
            OpenFoodFactsResolver(products: products), EnergyStarResolver(appliances: FakeApplianceDatabase()),
            ASUSPCFResolver(store: store), SpecResearchResolver(researcher: FakeSpecResearcher()),
            FactorModelResolver(store: store), EstimateResolver(),
        ]
        return ScanPipeline(vision: FixedVision(components: components), alternatives: FakeAlternativeSuggester(),
                            products: products, ladder: EvidenceLadder(resolvers: resolvers),
                            engine: ImpactEngine(reference: store), profile: .default)
    }

    private static func est(_ value: Double) -> [MetricKey: EstimateRange] {
        [.carbon: EstimateRange(value: value, low: value / 2, high: value * 2)]
    }

    /// The AI knew the garment but not its fiber or weight; a T-shirt's footprint is ~2–7 kg CO2e.
    static let shirt = IdentifiedComponent(name: "Graphic T-shirt", category: .clothing, boundingBox: .full,
                                           defaultUsage: UsageProfile(wearsPerYear: 40), estimates: est(5))
    /// "enamel" is not a reference material.
    static let mug = IdentifiedComponent(name: "Coffee mug", category: .household, boundingBox: .full,
                                         identifiers: Identifiers(materials: [MaterialShare(material: "enamel", percent: 100)]),
                                         quantities: Quantities(massKg: 0.35), estimates: est(2))
    static let stew = IdentifiedComponent(name: "Mystery stew", category: .food, boundingBox: .full,
                                          quantities: Quantities(servingKg: 0.3), defaultUsage: UsageProfile(servingsPerWeek: 1),
                                          estimates: est(3))
    static let lotion = IdentifiedComponent(name: "Hand lotion", category: .personalCare, boundingBox: .full,
                                            defaultUsage: UsageProfile(usesPerWeek: 7), estimates: est(0.5))
    static let drone = IdentifiedComponent(name: "Camera drone", category: .electronic, boundingBox: .full,
                                           quantities: Quantities(massKg: 0.9, deviceType: "drone"),
                                           defaultUsage: UsageProfile(hoursOnPerDay: 0.2), estimates: est(40))

    @Test func demoScenesOnlyAskAboutTheLunchTakeoutBox() async throws {
        for scene in DemoScene.allCases {
            let log = EventLog()
            let pipeline = ScanPipeline.demoTestPipeline(scene: scene)
            _ = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo) { log.append($0) }
            let asked = log.events.flatMap { event -> [SpecQuestion] in
                if case let .specQuestionsNeeded(questions) = event { questions } else { [] }
            }
            if scene == .meal {
                #expect(asked.map(\.componentName) == ["Takeout box"])
                #expect(asked.first?.topic == .material)
                #expect(asked.first?.options.map(\.label).contains("Foam") == true)
            } else {
                #expect(asked.isEmpty, "\(scene) should go straight to results")
            }
        }
    }

    @Test func asksOneQuestionPerT4ItemThatCanMoveUp() async throws {
        let pipeline = pipeline([Self.shirt, Self.mug, Self.lotion])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        #expect(result.components.allSatisfy { $0.metrics[.carbon]?.tier == .estimate })
        let questions = await pipeline.specQuestions(for: result.components)
        // Personal care has no factor-model carbon, so no answer would help; it is skipped.
        #expect(Set(questions.map(\.componentName)) == ["Graphic T-shirt", "Coffee mug"])
        #expect(Set(questions.map(\.componentID)).count == questions.count)
        let shirt = try #require(questions.first { $0.componentName == "Graphic T-shirt" })
        #expect(shirt.topic == .material)
        // Fiber answers fill a typical T-shirt mass, since the weight was unknown too.
        #expect(shirt.options.allSatisfy { $0.massKg == 0.2 })
        let mug = try #require(questions.first { $0.componentName == "Coffee mug" })
        #expect(mug.options.contains { $0.label == "Glass or ceramic" })
    }

    @Test func atMostThreeQuestionsBiggestCarbonFirst() async throws {
        // Five kinds of shirt ("Shirt 1"… would be one kind: a number is a printed size, not a kind).
        let kinds = ["Polo", "Dress", "Flannel", "Linen", "Denim"]
        let shirts = kinds.enumerated().map { index, kind in
            IdentifiedComponent(name: "\(kind) shirt", category: .clothing, boundingBox: .full,
                                quantities: Quantities(massKg: 0.3), estimates: Self.est(Double(index + 1)))
        }
        let pipeline = pipeline(shirts)
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let questions = await pipeline.specQuestions(for: result.components)
        #expect(questions.count == ScanPipeline.maxSpecQuestions)
        #expect(questions.map(\.componentName) == ["Denim shirt", "Linen shirt", "Flannel shirt"])
    }

    @Test func itemsAlreadyOnTheFactorModelAreNotAsked() async throws {
        let tee = IdentifiedComponent(name: "Cotton T-shirt", category: .clothing, boundingBox: .full,
                                      identifiers: Identifiers(materials: [MaterialShare(material: "cotton", percent: 100)]),
                                      quantities: Quantities(massKg: 0.2), estimates: Self.est(8))
        let pipeline = pipeline([tee])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        #expect(result.components[0].metrics[.carbon]?.tier == .factorModel)
        #expect(await pipeline.specQuestions(for: result.components).isEmpty)
    }

    @Test func answeringMovesTheItemToTheFactorModel() async throws {
        let pipeline = pipeline([Self.shirt])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let before = try #require(result.components.first)
        #expect(before.metrics[.carbon]?.tier == .estimate)
        let question = try #require(await pipeline.specQuestions(for: result.components).first)
        let cotton = try #require(question.options.first { $0.label == "Cotton or denim" })
        let wool = try #require(question.options.first { $0.label == "Wool" })

        let refined = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: before.id, option: cotton)])
        let after = try #require(refined.component(withID: before.id))
        let carbon = try #require(after.metrics[.carbon])
        #expect(carbon.tier == .factorModel)
        // 0.2 kg × (1.8 cotton + 11 garment processing) kg CO2e/kg ≈ 2.6 kg, narrower than the ±50% estimate.
        #expect(abs(carbon.value - 0.2 * (1.8 + 11)) < 0.01)
        #expect(carbon.relativeUncertainty < before.metrics[.carbon]!.relativeUncertainty)
        #expect(carbon.sources.contains { $0.title == "Your answer: Cotton or denim" })
        #expect(after.metrics[.water]?.tier == .factorModel)
        #expect(after.identifiers.materials == [MaterialShare(material: "cotton", percent: 100)])
        #expect(refined.totals[.carbon]!.value != result.totals[.carbon]!.value)
        #expect(await pipeline.specQuestions(for: refined.components).isEmpty)

        // Wool is the heavier footprint, so the same garment comes out higher.
        let woolResult = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: before.id, option: wool)])
        #expect(woolResult.component(withID: before.id)!.metrics[.carbon]!.value > carbon.value)
    }

    @Test func foodTypeAndDeviceKindAnswersResolve() async throws {
        let pipeline = pipeline([Self.stew, Self.drone])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let questions = await pipeline.specQuestions(for: result.components)
        let stewQuestion = try #require(questions.first { $0.componentName == "Mystery stew" })
        #expect(stewQuestion.topic == .foodType)
        let droneQuestion = try #require(questions.first { $0.componentName == "Camera drone" })
        #expect(droneQuestion.topic == .deviceKind)

        let beef = try #require(stewQuestion.options.first { $0.foodGroup == "beef" })
        let veg = try #require(stewQuestion.options.first { $0.foodGroup == "other_vegetables" })
        let gadget = try #require(droneQuestion.options.first { $0.label == "Small gadget" })
        let stewID = stewQuestion.componentID, droneID = droneQuestion.componentID
        let beefy = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: stewID, option: beef),
                                                                  SpecAnswer(componentID: droneID, option: gadget)])
        let veggie = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: stewID, option: veg)])
        let beefStew = try #require(beefy.component(withID: stewID)?.metrics[.carbon])
        let vegStew = try #require(veggie.component(withID: stewID)?.metrics[.carbon])
        #expect(beefStew.tier == .factorModel)
        #expect(beefStew.value > vegStew.value * 10)
        let drone = try #require(beefy.component(withID: droneID))
        #expect(drone.metrics[.carbon]?.tier == .factorModel)
        #expect(drone.metrics[.yearlyElectricity] != nil)
        // An unanswered item keeps its estimate.
        #expect(veggie.component(withID: droneID)?.metrics == result.component(withID: droneID)?.metrics)
    }

    @Test func noAnswersLeavesTheResultAlone() async throws {
        let pipeline = pipeline([Self.shirt, Self.mug])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let refined = await pipeline.refining(result, specAnswers: [])
        #expect(refined.components == result.components)
        #expect(refined.totals == result.totals)
    }

    // MARK: Q1: no single-material questions about things that are not single-material

    /// A car filed as household once got "Wood / Plastic / Metal…", and "Wood" turned ≈9 t into 855 kg.
    @Test func compositeAndBackgroundItemsAreNotAskedWhatTheyAreMadeOf() async throws {
        let suv = IdentifiedComponent(name: "Electric SUV", category: .household, boundingBox: .full,
                                      identifiers: Identifiers(materials: [MaterialShare(material: "car_body", percent: 60),
                                                                           MaterialShare(material: "battery_pack", percent: 25)]),
                                      quantities: Quantities(massKg: 1900), estimates: Self.est(9000))
        let unknownCar = IdentifiedComponent(name: "Hatchback", category: .household, boundingBox: .full,
                                             estimates: Self.est(8000))
        let background = IdentifiedComponent(name: "Wooden bench (background)", category: .household, boundingBox: .full,
                                             quantities: Quantities(massKg: 15), estimates: Self.est(10))
        let pipeline = pipeline([suv, unknownCar, background])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        #expect(result.components.allSatisfy { $0.metrics[.carbon]?.tier == .estimate })
        #expect(await pipeline.specQuestions(for: result.components).isEmpty)
    }

    @Test func wornThingsThatAreNotTextilesGetNoFiberQuestion() async throws {
        let items = ["Eyeglasses (tortoiseshell)", "Bike helmet", "Running sneakers", "Wristwatch"].map {
            IdentifiedComponent(name: $0, category: .clothing, boundingBox: .full, estimates: Self.est(1))
        }
        let acetate = IdentifiedComponent(name: "Frames", category: .clothing, boundingBox: .full,
                                          identifiers: Identifiers(materials: [MaterialShare(material: "acetate", percent: 90)]),
                                          estimates: Self.est(1))
        let pipeline = pipeline(items + [acetate])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        #expect(await pipeline.specQuestions(for: result.components).isEmpty)
    }

    /// The AI saw the item, so a material answer that moves its carbon more than 3× from that estimate is not offered.
    @Test func materialAnswersFarFromTheEstimateAreNotOffered() async throws {
        let bench = IdentifiedComponent(name: "Storage bench", category: .household, boundingBox: .full,
                                        quantities: Quantities(massKg: 20), estimates: Self.est(40))
        let pipeline = pipeline([bench])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let question = try #require(await pipeline.specQuestions(for: result.components).first)
        #expect(question.topic == .material)
        // 20 kg of wood is ~9 kg CO2e, 4.4× under the estimate; plastic, steel and the rest are within 3×.
        #expect(!question.options.contains { $0.label == "Wood" })
        for option in question.options {
            let refined = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: question.componentID, option: option)])
            let carbon = try #require(refined.components.first?.metrics[.carbon])
            #expect(carbon.value <= 40 * ScanPipeline.refinementBand && carbon.value >= 40 / ScanPipeline.refinementBand)
        }
    }

    @Test func aDetailAnswerCanBeTakenBack() async throws {
        let pipeline = pipeline([Self.shirt])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let original = try #require(result.components.first)
        let question = try #require(await pipeline.specQuestions(for: result.components).first)
        let wool = try #require(question.options.first { $0.label == "Wool" })
        let refined = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: original.id, option: wool)])
        let answered = try #require(refined.components.first)
        #expect(answered.detailAnswer?.label == "Wool")
        #expect(answered.metrics[.carbon]?.tier == .factorModel)

        let undone = await pipeline.undoingDetail(of: original.id, in: refined)
        let restored = try #require(undone.components.first)
        #expect(restored.detailAnswer == nil)
        #expect(restored.metrics == original.metrics)
        #expect(restored.identifiers == original.identifiers)
        #expect(restored.quantities == original.quantities)
        #expect(undone.totals == result.totals)
        // Saved scans keep the answer, so the sheet can still offer to take it back after a relaunch.
        let decoded = try JSONDecoder().decode(Component.self, from: JSONEncoder().encode(answered))
        #expect(decoded.detailAnswer == answered.detailAnswer)
    }

    // MARK: Q4: deterministic questions for foods whose group swings

    /// A chia pudding came back as milk, soy milk or pulses across runs (land 2.8× apart) and nothing asked.
    @Test func milkDishesAskDairyOrPlant() async throws {
        let pudding = IdentifiedComponent(name: "Chia pudding", category: .food, boundingBox: .full,
                                          quantities: Quantities(servingKg: 0.2, foodGroup: "other_pulses"),
                                          estimates: Self.est(0.6))
        let pipeline = pipeline([pudding])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let before = try #require(result.components.first)
        #expect(before.metrics[.carbon]?.tier == .factorModel)
        #expect(before.usage?.servingsPerWeek == 2)
        let question = try #require(await pipeline.specQuestions(for: result.components).first)
        #expect(question.topic == .foodType)
        #expect(question.options.map(\.foodGroup) == ["milk", "soy_milk"])

        let dairy = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: before.id, option: question.options[0])])
        let plant = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: before.id, option: question.options[1])])
        let dairyCarbon = try #require(dairy.components.first?.metrics[.carbon])
        let plantCarbon = try #require(plant.components.first?.metrics[.carbon])
        #expect(dairyCarbon.tier == .factorModel)
        #expect(abs(dairyCarbon.value - 0.2 * 3.15) < 1e-9)
        #expect(abs(plantCarbon.value - 0.2 * 0.98) < 1e-9)
        #expect(dairyCarbon.sources.contains { $0.title == "Your answer: Dairy milk" })
        // A milk dish's typical week is milk's, not the pulses' it was filed under.
        #expect(dairy.components.first?.usage?.servingsPerWeek == UsageDefaults.servingsByGroup["milk"])
        #expect(dairy.components.first?.detailAnswer != nil)
    }

    @Test func proteinIsAskedOnlyWhenTheNameDoesNotSayIt() async throws {
        let burger = IdentifiedComponent(name: "Burger", category: .food, boundingBox: .full,
                                         quantities: Quantities(servingKg: 0.12, foodGroup: "beef"), estimates: Self.est(8))
        let beefBurger = IdentifiedComponent(name: "Beef burger", category: .food, boundingBox: .full,
                                             quantities: Quantities(servingKg: 0.12, foodGroup: "beef"), estimates: Self.est(8))
        let oatMilk = IdentifiedComponent(name: "Oat milk", category: .food, boundingBox: .full,
                                          quantities: Quantities(volumeLiters: 0.25, foodGroup: "soy_milk"), estimates: Self.est(0.3))
        let pipeline = pipeline([burger, beefBurger, oatMilk])
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let questions = await pipeline.specQuestions(for: result.components)
        #expect(questions.map(\.componentName) == ["Burger"])
        let question = try #require(questions.first)
        #expect(question.options.map(\.foodGroup) == ["beef", "pork", "poultry", "fish_farmed", "tofu"])
        let tofu = try #require(question.options.last)
        let refined = await pipeline.refining(result, specAnswers: [SpecAnswer(componentID: question.componentID, option: tofu)])
        let carbon = try #require(refined.component(withID: question.componentID)?.metrics[.carbon])
        #expect(abs(carbon.value - 0.12 * 3.16) < 1e-9)
    }
}

private struct FixedVision: VisionIdentifier {
    var components: [IdentifiedComponent]

    func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        IdentifyResponse(components: components, sceneTitle: "Test")
    }
}

extension ScanPipeline {
    /// The demo services' pipeline: fake identify, research and records; real factors and engine.
    static func demoTestPipeline(scene: DemoScene) -> ScanPipeline {
        let store = ReferenceStore.bundled
        let products = FakeProductDatabase()
        let resolvers: [any MetricResolver] = [
            OpenFoodFactsResolver(products: products), EnergyStarResolver(appliances: FakeApplianceDatabase()),
            ASUSPCFResolver(store: store), SpecResearchResolver(researcher: FakeSpecResearcher()),
            FactorModelResolver(store: store), EstimateResolver(),
        ]
        return ScanPipeline(vision: FakeVisionIdentifier(scene: scene), alternatives: FakeAlternativeSuggester(),
                            products: products, ladder: EvidenceLadder(resolvers: resolvers),
                            engine: ImpactEngine(reference: store), profile: .default)
    }
}
