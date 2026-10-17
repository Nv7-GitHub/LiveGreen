import Foundation
import Testing
@testable import GreenCore

@Suite("OpenFoodFactsClient")
struct OpenFoodFactsClientTests {
    func client(_ transport: MockTransport) -> OpenFoodFactsClient {
        OpenFoodFactsClient(retry: .instant(), transport: transport)
    }

    @Test func buildsProductRequest() async throws {
        let transport = MockTransport([.fixture("off/product_7622210449283.json")])
        _ = try await client(transport).product(gtin: "7622210449283")
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/api/v2/product/7622210449283.json")
        #expect(request.url?.host() == "world.openfoodfacts.org")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "LiveGreen/1.0 (HackHarvard)")
        let fields = try #require(request.queryValue("fields")).split(separator: ",")
        #expect(fields.contains("ecoscore_data"))
        #expect(fields.contains("packagings"))
        #expect(fields.contains("product_quantity"))
    }

    @Test func decodesAgribalyseRecord() async throws {
        let transport = MockTransport([.fixture("off/product_7622210449283.json")])
        let record = try #require(try await client(transport).product(gtin: "7622210449283"))
        #expect(record.name == "Prince")
        #expect(record.brand == "Mondelez Schweiz GmbH")
        #expect(record.category == .food)
        #expect(record.netMassKg == 0.3)
        #expect(record.carbonKgPerKg == 6.67)
        #expect(record.sourceURL.absoluteString == "https://world.openfoodfacts.org/product/7622210449283")

        // Stage split: agriculture 5.31 / processing+packaging 1.089 / transport+distribution 0.2789.
        let total = 5.31 + 0.209 + 0.88 + 0.252 + 0.0269
        #expect(abs((record.stageShares[.materials] ?? 0) - 5.31 / total) < 1e-9)
        #expect(abs((record.stageShares[.manufacturing] ?? 0) - 1.089 / total) < 1e-9)
        #expect(record.stageShares[.use] == nil, "zero consumption stage omitted")

        #expect(record.packaging.count == 2)
        #expect(record.packaging[0] == PackagingPart(material: "plástico", massG: 3.35, isPlastic: true, recyclable: true))
        #expect(record.packaging[1] == PackagingPart(material: "cartón ondulado", massG: 3.54, isPlastic: false, recyclable: true))

        let metrics = record.measuredMetrics()
        let carbon = try #require(metrics[.carbon])
        #expect(abs(carbon.value - 2.001) < 1e-9)
        #expect(carbon.tier == .exactRecord)
        #expect(carbon.sources.first?.url == record.sourceURL)
        #expect(abs(carbon.low - 2.001 * 0.8) < 1e-9)
        #expect(abs((metrics[.recyclablePercent]?.value ?? 0) - 100) < 1e-9)

        let perServing = record.measuredMetrics(massKg: 0.03)
        #expect(abs((perServing[.carbon]?.value ?? 0) - 0.2001) < 1e-9)
    }

    @Test func decodesPlasticPackagingWithoutAgribalyse() async throws {
        let transport = MockTransport([.fixture("off/product_3274080005003.json")])
        let record = try #require(try await client(transport).product(gtin: "3274080005003"))
        #expect(record.carbonKgPerKg == nil)
        #expect(record.netMassKg == 1.5, "1500 ml ≈ 1.5 kg")
        #expect(record.packaging.map(\.material) == ["pet-1-polyethylene-terephthalate", "hdpe-2-high-density-polyethylene", "plastic"])
        #expect(record.packaging.allSatisfy { $0.isPlastic })
        #expect(abs((record.plasticMassG ?? 0) - 21.88) < 1e-9)
        let metrics = record.measuredMetrics()
        #expect(metrics[.carbon] == nil)
        #expect(metrics[.plasticMass]?.tier == .exactRecord)
        #expect(metrics[.recyclablePercent] == nil, "the cap has no recycling status")
    }

    @Test func unknownProductIsNil() async throws {
        let transport = MockTransport([.fixture("off/product_missing.json")])
        #expect(try await client(transport).product(gtin: "00000017") == nil)
        let notFound = MockTransport([.json("{\"status\":0}", status: 404)])
        #expect(try await client(notFound).product(gtin: "12345670") == nil)
    }

    @Test func invalidGTINSkipsNetwork() async throws {
        let transport = MockTransport([])
        #expect(try await client(transport).product(gtin: "abc") == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func serverErrorThrows() async throws {
        let transport = MockTransport([.json("oops", status: 500), .json("oops", status: 500), .json("oops", status: 500)])
        await #expect(throws: GreenCoreError.http(status: 500, body: "oops")) {
            _ = try await client(transport).product(gtin: "7622210449283")
        }
        #expect(transport.requests.count == 3)
    }

    @Test func tagHelpers() {
        #expect(OFFTags.strip("en:pet-1-polyethylene-terephthalate") == "pet-1-polyethylene-terephthalate")
        #expect(OFFTags.isPlastic("pp-5-polypropylene"))
        #expect(!OFFTags.isPlastic("aluminium"))
        #expect(OFFTags.isRecyclable("en:recycle-in-sorting-bin") == true)
        #expect(OFFTags.isRecyclable("en:discard") == false)
        #expect(OFFTags.isRecyclable("en:unknown") == nil)
        #expect(OFFProductPayload.massKg(quantity: .string("33"), unit: "cl") == 0.33)
        #expect(OFFTags.repairingMojibake("PlÃ¡stico") == "Plástico")
    }

    @Test func categoriesGiveTheDrinkFoodGroup() {
        #expect(OFFProductPayload.foodGroup(categories: ["en:beverages", "en:carbonated-drinks", "en:carbonated-waters"])
            == "bottled_water")
        #expect(OFFProductPayload.foodGroup(categories: ["en:beverages", "en:sodas"]) == "soft_drinks")
        #expect(OFFProductPayload.foodGroup(categories: ["en:snacks"]) == nil)
    }
}
