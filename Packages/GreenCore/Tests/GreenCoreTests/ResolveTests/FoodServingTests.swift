import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Food is annualized per serving, so package-level values must be scaled to one serving (spec §5.6).
@Suite("Food serving basis and plastic split")
struct FoodServingTests {
    private let box = ProductRecord(
        gtin: "1234567890128", name: "Cereal 1 kg", category: .food, netMassKg: 1.0, carbonKgPerKg: 2.0,
        packaging: [PackagingPart(material: "plastic", massG: 20, isPlastic: true, recyclable: false)],
        sourceURL: URL(string: "https://world.openfoodfacts.org/product/1234567890128")!)

    private func resolveOFF(_ component: Component, record: ProductRecord) async throws -> ResolverOutput {
        let resolver = OpenFoodFactsResolver(products: FakeProductDatabase(records: [record.gtin: record]))
        let request = ResolutionRequest(component: component, metrics: Set(component.category.applicableMetrics),
                                        profile: .default)
        return try await resolver.resolve(request)
    }

    @Test func barcodeWithoutServingUsesTheReferenceServing() async throws {
        let component = Component(name: "Cereal", category: .food, identifiers: Identifiers(gtin: box.gtin),
                                  quantities: Quantities(massKg: 1.0))
        let output = try await resolveOFF(component, record: box)
        #expect(abs(try #require(output.metrics[.carbon]).value - 2.0 * FoodServing.referenceKg) < 1e-9)
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 20 * FoodServing.referenceKg) < 1e-9)
        #expect(output.plasticPackagingShare == 1)
    }

    @Test func statedOrRecordServingWins() async throws {
        var record = box
        record.servingKg = 0.04
        let component = Component(name: "Cereal", category: .food, identifiers: Identifiers(gtin: box.gtin))
        let output = try await resolveOFF(component, record: record)
        #expect(abs(try #require(output.metrics[.carbon]).value - 0.08) < 1e-9)
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 0.8) < 1e-9)

        var stated = component
        stated.quantities.servingKg = 0.05
        #expect(abs(try #require(try await resolveOFF(stated, record: record).metrics[.carbon]).value - 0.1) < 1e-9)
    }

    @Test func packagedDrinkDefaultsToOneCan() throws {
        let twelvePack = Component(name: "Seltzer 12-pack", category: .food, identifiers: Identifiers(gtin: "0071537003673"),
                                   quantities: Quantities(massKg: 4.3, foodGroup: "bottled_water"))
        #expect(FoodServing.servingKg(twelvePack) == FoodServing.drinkReferenceKg)
        let can = Component(name: "Seltzer", category: .food, identifiers: Identifiers(gtin: "0071537003673"),
                            quantities: Quantities(volumeLiters: 0.355))
        #expect(FoodServing.servingKg(can) == 0.355)
        let water = try #require(FactorModelResolver(store: .bundled).food(can).metrics[.water])
        #expect(abs(water.value - 0.355 * 3) < 1e-9)
    }

    @Test func unpackagedPortionIsOneServing() {
        let burger = Component(name: "Burger", category: .food, quantities: Quantities(massKg: 0.25, foodGroup: "beef"))
        #expect(FoodServing.servingKg(burger) == 0.25)
    }

    @Test func factorModelScalesPackagingToOneServing() throws {
        let rice = Component(name: "Rice", category: .food,
                             identifiers: Identifiers(materials: [MaterialShare(material: "pp", percent: 100)]),
                             quantities: Quantities(massKg: 1.0, servingKg: 0.1, packagingMassG: 30, foodGroup: "rice"))
        let output = FactorModelResolver(store: .bundled).food(rice)
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 3) < 1e-9)
        #expect(output.plasticPackagingShare == 1)
    }

    @Test func plasticSplitFollowsTheResolver() async throws {
        let ladder = EvidenceLadder(resolvers: [FactorModelResolver(store: .bundled)])
        let laptop = await ladder.resolve(Component(name: "Laptop", category: .electronic,
                                                    quantities: Quantities(deviceType: "laptop")), profile: .default)
        let split = try #require(laptop.plasticSplit)
        #expect(split.packaging.value == 0)
        #expect(split.item.value == laptop.metrics[.plasticMass]?.value)

        let cache = InMemoryResolutionCache()
        let cached = EvidenceLadder(resolvers: [OpenFoodFactsResolver(products: FakeProductDatabase(records: [box.gtin: box]))],
                                    cache: cache)
        let cereal = Component(name: "Cereal", category: .food, identifiers: Identifiers(gtin: box.gtin))
        _ = await cached.resolve(cereal, profile: .default)
        let hit = try #require(await cached.cached(cereal))
        #expect(hit.plasticPackagingShare == 1)
        #expect(hit.plasticSplit?.item.value == 0)
    }
}
