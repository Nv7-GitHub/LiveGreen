import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Vehicles have their own category and model (D1): production from glider and battery, driving by powertrain,
/// a 15-year life, and no household water or decomposition.
@Suite("Vehicle model")
struct VehicleModelTests {
    private struct FixedVision: VisionIdentifier {
        var components: [IdentifiedComponent]
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
            IdentifyResponse(components: components, sceneTitle: nil)
        }
    }

    let engine = ImpactEngine(reference: ReferenceStore.bundled)
    let resolver = FactorModelResolver(store: .bundled)

    func resolved(_ name: String, kg: Double, _ powertrain: Powertrain?, usage: UsageProfile? = nil) -> Component {
        var car = Component(name: name, category: .vehicle, quantities: Quantities(massKg: kg, powertrain: powertrain),
                            usage: usage)
        let output = resolver.vehicle(car, profile: .default)
        car.metrics = output.metrics
        car.stageShares = output.stageShares
        return car
    }

    func perYear(_ component: Component) throws -> Double {
        try #require(engine.yearly(.carbon, of: component)).value
    }

    @Test func drivingRanksTheEVBelowThePetrolCar() throws {
        let kia = resolved("Kia Sportage", kg: 1600, .petrol)
        let tesla = resolved("Tesla Model Y", kg: 1950, .electric)
        let kiaYear = try perYear(kia), teslaYear = try perYear(tesla)
        // A compact petrol SUV: ≈8 t to make over 15 years plus ≈4.4 t a year of fuel.
        #expect((4000...6000).contains(kiaYear), "\(kiaYear)")
        #expect(teslaYear < kiaYear / 2, "EV \(teslaYear) vs petrol \(kiaYear)")
        // Production includes the EV's battery, so the EV costs more to make.
        let kiaModel = try #require(engine.vehicleModel(for: kia))
        let teslaModel = try #require(engine.vehicleModel(for: tesla))
        #expect((7000...9000).contains(kiaModel.production.value))
        #expect(teslaModel.production.value > kiaModel.production.value)
        #expect(teslaModel.batteryKWh > 60 && teslaModel.batteryKWh < 90)
        // A hybrid sits between them.
        let hybrid = try perYear(resolved("Kia Sportage hybrid", kg: 1700, .hybrid))
        #expect(teslaYear < hybrid && hybrid < kiaYear)
    }

    @Test func vehiclesLastFifteenYearsAndShowNoHouseholdMetrics() throws {
        let car = resolved("Hatchback car", kg: 1400, nil)
        #expect(engine.lifespan(of: car).value == 15)
        guard case .lifetime(let lifespan) = engine.annualBasis(for: car) else { Issue.record("not a durable"); return }
        #expect(lifespan.value == 15)
        #expect(car.metrics[.water] == nil && car.metrics[.decompositionTime] == nil)
        #expect(!Category.vehicle.applies(.water) && !Category.vehicle.applies(.decompositionTime))
        #expect(try #require(car.metrics[.recyclablePercent]).value == 80)
        #expect(abs(try #require(car.metrics[.plasticMass]).value - 140_000) < 1)
        // Petrol is assumed without a powertrain, and a petrol car draws no grid electricity.
        #expect(car.metrics[.yearlyElectricity] == nil)
        let use = try #require(car.stageShares[.use])
        #expect(use > 0.8 && use < 0.95)
        #expect(Category.vehicle.systemImage == "car")
    }

    @Test func anEVChargesFromTheGrid() throws {
        let leaf = resolved("Nissan Leaf", kg: 1500, .electric)
        let kWh = try #require(leaf.metrics[.yearlyElectricity]).value
        // 18,500 km at ≈0.165 kWh/km at the wall.
        #expect((2500...3600).contains(kWh), "\(kWh)")
        let cleaner = UserProfile(region: Region(countryCode: "NO"))
        let output = resolver.vehicle(Component(name: "Nissan Leaf", category: .vehicle,
                                                quantities: Quantities(massKg: 1500, powertrain: .electric)), profile: cleaner)
        let cleanCarbon = try #require(output.metrics[.carbon]).value
        #expect(cleanCarbon < (try #require(leaf.metrics[.carbon]).value))
    }

    @Test func distanceIsEditableAndMovesTheUsePhase() throws {
        let car = resolved("Sedan", kg: 1500, .petrol)
        let editable = engine.editableUsage(for: car)
        #expect(editable.map(\.field) == [.kmPerWeek])
        #expect(abs((editable.first?.value ?? 0) - 18_500 / 52) < 1e-9)
        let before = try perYear(car)
        let model = try #require(engine.vehicleModel(for: car))
        let doubled = engine.applyingUsage(UsageProfile(kmPerWeek: 2 * 18_500 / 52), to: car, profile: .default)
        let added = model.drivingKgCO2e(kmPerYear: 18_500, gramsPerKWh: engine.gridGramsPerKWh(for: .default))
        #expect(abs(try perYear(doubled) - (before + added)) < 1)
        let useShare = try #require(doubled.stageShares[.use])
        #expect(useShare > (try #require(car.stageShares[.use])))
    }

    @Test func secondHandDiscountsOnlyProduction() throws {
        let car = resolved("Sedan", kg: 1500, .petrol)
        let carbon = try #require(car.metrics[.carbon]).value
        let driving = try #require(engine.drivingCarbonPerYear(of: car, profile: .default)) * 15
        let used = engine.secondHand(car, share: 0.5, profile: .default)
        #expect(abs(try #require(used.metrics[.carbon]).value - (driving + (carbon - driving) * 0.5)) < 1e-6)
    }

    @Test func researchedProductionGetsDriving() async throws {
        let pcf = FakeMetricResolver(tier: .researchedSpec, name: "LCA", values: [.carbon: 9000])
        let store = ReferenceStore.bundled
        let car = IdentifiedComponent(name: "Kia Sportage", category: .vehicle, boundingBox: .full,
                                      identifiers: Identifiers(brand: "Kia", modelLine: "Sportage", confidence: .high),
                                      quantities: Quantities(massKg: 1600, powertrain: .petrol))
        let pipeline = ScanPipeline(vision: FixedVision(components: [car]),
                                    alternatives: FakeAlternativeSuggester(), products: FakeProductDatabase(),
                                    ladder: EvidenceLadder(resolvers: [pcf, FactorModelResolver(store: store)]),
                                    engine: ImpactEngine(reference: store), profile: .default)
        let component = try #require(try await pipeline.run(image: Data([1]), hints: .none, mode: .photo).components.first)
        let driving = try #require(pipeline.engine.drivingCarbonPerYear(of: component, profile: .default)) * 15
        #expect(abs(try #require(component.metrics[.carbon]).value - (9000 + driving)) < 1e-6)
    }

    @Test func roadVehiclesFiledElsewhereBecomeVehicles() {
        func isVehicle(_ name: String, _ category: GreenCore.Category, kg: Double?, _ powertrain: Powertrain? = nil) -> Bool {
            VehicleModel.isVehicle(name: name, category: category, quantities: Quantities(massKg: kg, powertrain: powertrain))
        }
        #expect(isVehicle("Hatchback car (background)", .household, kg: 1500))
        #expect(isVehicle("White electric SUV", .electronic, kg: 1900))
        #expect(isVehicle("Tesla Model Y", .electronic, kg: nil, .electric))
        #expect(!isVehicle("Child car seat", .household, kg: 9))
        #expect(!isVehicle("Hybrid bike", .household, kg: 13))
        #expect(!isVehicle("Vans sneakers", .clothing, kg: 0.9))
        #expect(!isVehicle("Sofa", .household, kg: 40))
    }

    @Test func powertrainDecodesLooselyWithoutFailing() throws {
        func decode(_ json: String) throws -> Quantities {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Quantities.self, from: Data(json.utf8))
        }
        #expect(try decode(#"{"mass_kg": 1900, "powertrain": "EV"}"#).powertrain == .electric)
        #expect(try decode(#"{"powertrain": "Plug-in hybrid"}"#).powertrain == .plugInHybrid)
        #expect(try decode(#"{"powertrain": "gasoline"}"#).powertrain == .petrol)
        #expect(try decode(#"{"mass_kg": 1, "powertrain": "warp drive"}"#).powertrain == nil)
        let quantities = Quantities(massKg: 1500, powertrain: .plugInHybrid, consumable: true, usesPerContainer: 80)
        #expect(try JSONDecoder().decode(Quantities.self, from: JSONEncoder().encode(quantities)) == quantities)
    }

    @Test func vehiclesGetNoMaterialQuestion() {
        let car = Component(name: "Electric SUV", category: .vehicle, quantities: Quantities(massKg: 1900))
        #expect(SpecQuestionCatalog.candidates(for: car, store: .bundled).isEmpty)
    }

    @Test func savedScansWithVehiclesRoundTrip() throws {
        let result = ScanResult(title: "Street", components: [resolved("Sedan", kg: 1500, .diesel)])
        let decoded = try JSONDecoder().decode(ScanResult.self, from: JSONEncoder().encode(result))
        #expect(decoded.components.first?.category == .vehicle)
        #expect(decoded.components.first?.quantities.powertrain == .diesel)
    }
}
