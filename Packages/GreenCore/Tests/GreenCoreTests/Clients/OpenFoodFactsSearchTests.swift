import Foundation
import Synchronization
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Branded food without a barcode is looked up by brand and name (C4 of the image QA: 544 metrics, none from a
/// record, although Open Food Facts has Lay's and Nerds Gummy Clusters). Fixtures are real search responses, trimmed.
@Suite("Open Food Facts name search")
struct OpenFoodFactsSearchTests {
    func client(_ transport: MockTransport) -> OpenFoodFactsClient {
        OpenFoodFactsClient(retry: .instant(), transport: transport)
    }

    static let saltAndVinegarCarbon = 1.541250051

    @Test func buildsASearchRequest() async throws {
        let transport = MockTransport([.fixture("off/search_lays_salt_vinegar.json")])
        _ = try await client(transport).searchProduct(brand: "Lay's", name: "Lay's Salt & Vinegar Potato Chips (bag)")
        let request = try #require(transport.requests.first)
        #expect(request.url?.host() == "search.openfoodfacts.org")
        #expect(request.url?.path() == "/search")
        #expect(request.queryValue("q") == "Lay's Salt & Vinegar Potato Chips", "the brand said once, no aside")
        #expect(request.url?.query?.contains("Salt%20%26%20Vinegar") == true, "the ampersand stays in the query")
        #expect(request.queryValue("page_size") == "20")
        #expect(request.queryValue("fields")?.split(separator: ",").contains("ecoscore_data") == true)
        #expect(request.timeoutInterval == 5)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "LiveGreen/1.0 (HackHarvard)")
        #expect(ProductNameMatch.query(brand: "Nerds", name: "Gummy Clusters candy") == "Nerds Gummy Clusters candy")
    }

    @Test func findsTheVariantThatWasNamed() async throws {
        let transport = MockTransport([.fixture("off/search_lays_salt_vinegar.json")])
        let record = try #require(try await client(transport).searchProduct(brand: "Lay's", name: "Lay's Salt & Vinegar potato chips"))
        #expect(record.carbonKgPerKg == Self.saltAndVinegarCarbon)
        #expect(record.brand?.contains("Lay's") == true)
        #expect(["0028400017503", "6009510804775", "0060410010914"].contains(record.gtin))
        #expect(record.name.lowercased().contains("vinegar"))
        #expect(record.sourceURL.absoluteString == "https://world.openfoodfacts.org/product/\(record.gtin)")
    }

    @Test func aDifferentVariantIsNotUsed() async throws {
        // 28: a Salt & Vinegar bag was named "Classic"; neither may take the other's record.
        let saltAndVinegar = MockTransport([.fixture("off/search_lays_salt_vinegar.json")])
        #expect(try await client(saltAndVinegar).searchProduct(brand: "Lay's", name: "Lay's Classic Potato Chips") == nil)
        let classic = MockTransport([.fixture("off/search_lays_classic.json")])
        #expect(try await client(classic).searchProduct(brand: "Lay's", name: "Lay's Salt and Vinegar chips") == nil)
        let classicAgain = MockTransport([.fixture("off/search_lays_classic.json")])
        let plain = try #require(try await client(classicAgain).searchProduct(brand: "Lay's", name: "Lay's Classic Potato Chips"))
        #expect(plain.gtin == "0028400097802", "the closest name first in the search's order: \(plain.name)")
        #expect(plain.carbonKgPerKg == Self.saltAndVinegarCarbon, "Agribalyse's potato-crisps figure")
    }

    @Test func theFigureMostRecordsAgreeOnWins() async throws {
        // Six Nerds Gummy Clusters records: five filed as "Candies, all types" (1.72), one as "Jelly candy" (1.56).
        let transport = MockTransport([.fixture("off/search_nerds_gummy_clusters.json")])
        let record = try #require(try await client(transport).searchProduct(brand: "Nerds", name: "Nerds Gummy Clusters candy packs"))
        #expect(record.carbonKgPerKg == 1.722810514)
        #expect(record.brand == "Nerds")
    }

    @Test func aFailedSearchThrowsOnceWithoutRetrying() async throws {
        let transport = MockTransport([.json("unavailable", status: 503), .json("unavailable", status: 503)])
        await #expect(throws: GreenCoreError.http(status: 503, body: "unavailable")) {
            _ = try await client(transport).searchProduct(brand: "Lay's", name: "Lay's Classic")
        }
        #expect(transport.requests.count == 1)
    }

    // MARK: Matching

    static func record(_ name: String, brand: String?, carbon: Double? = 1.5, gtin: String = "1") -> ProductRecord {
        ProductRecord(gtin: gtin, name: name, brand: brand, category: .food, carbonKgPerKg: carbon,
                      sourceURL: URL(string: "https://world.openfoodfacts.org/product/\(gtin)")!)
    }

    @Test func aMatchNeedsTheBrandMostOfTheNameAndACarbonFigure() {
        func matches(_ record: ProductRecord, brand: String = "Lay's", name: String) -> Bool {
            ProductNameMatch.best(brand: brand, name: name, among: [record]) != nil
        }
        #expect(!matches(Self.record("Salt and malt vinegar crisps", brand: "Waitrose"), name: "Lay's Salt & Vinegar"))
        #expect(matches(Self.record("Lay's Salt & Vinegar", brand: nil), name: "Lay's salt and vinegar chips"),
                "the brand can be in the record's name")
        #expect(matches(Self.record("Potato Chips Salt & Vinegar Flavour", brand: "Lay's, Simba"),
                        name: "Lay's Salt & Vinegar potato chips"), "any of the record's brands")
        #expect(!matches(Self.record("Lays salt & vinegar", brand: "Lay's", carbon: nil), name: "Lay's Salt & Vinegar"),
                "no carbon, nothing to add")
        #expect(matches(Self.record("Lay's Classic Potato chips", brand: "Lay's"), name: "Lay's potato chips"),
                "no flavour named takes the plain one")
        #expect(!matches(Self.record("Lay's Stax Original", brand: "Lay's"), name: "Lay's Classic potato chips"),
                "too little of the name")
        #expect(!matches(Self.record("Lay's Potato Chips", brand: "Lay's"), name: "Lay's"), "a brand alone is too vague")
        #expect(matches(Self.record("nerds gummy clusters", brand: "Nerds"), brand: "Nerds", name: "Gummy Clusters (one pouch)"))
        #expect(!matches(Self.record("Nerds Rope Very Berry", brand: "Nerds"), brand: "Nerds", name: "Nerds Rope"))
        #expect(ProductNameMatch.words("Lay’s Sea-Salted Chips, 2.5 oz") == ["lay", "sea", "salt", "chip", "oz"])
    }

    // MARK: In the ladder

    /// Counts searches and GTIN lookups.
    final class CountingSearch: ProductDatabase, Sendable {
        let database: FakeProductDatabase
        private let counts = Mutex((gtin: 0, search: 0))

        init(_ records: [ProductRecord]) {
            database = FakeProductDatabase(records: Dictionary(uniqueKeysWithValues: records.map { ($0.gtin, $0) }))
        }

        var searches: Int { counts.withLock { $0.search } }
        var lookups: Int { counts.withLock { $0.gtin } }

        func product(gtin: String) async throws -> ProductRecord? {
            counts.withLock { $0.gtin += 1 }
            return try await database.product(gtin: gtin)
        }

        func searchProduct(brand: String, name: String) async throws -> ProductRecord? {
            counts.withLock { $0.search += 1 }
            return try await database.searchProduct(brand: brand, name: name)
        }
    }

    private func request(_ component: Component) -> ResolutionRequest {
        ResolutionRequest(component: component, metrics: Set(component.category.applicableMetrics), profile: .default)
    }

    @Test func brandedFoodWithoutABarcodeGetsTheRecordsCarbon() async throws {
        let products = CountingSearch([Self.record("Lays salt & vinegar", brand: "Lay's", carbon: Self.saltAndVinegarCarbon,
                                                   gtin: "0060410010914")])
        let chips = Component(name: "Lay's Salt & Vinegar chips", category: .food, identifiers: Identifiers(brand: "Lay's"),
                              quantities: Quantities(massKg: 0.03, servingKg: 0.028, foodGroup: "potatoes"))
        let output = try await OpenFoodFactsResolver(products: products).resolve(request(chips))
        let carbon = try #require(output.metrics[.carbon])
        #expect(abs(carbon.value - Self.saltAndVinegarCarbon * 0.028) < 1e-9, "per kg × the serving")
        #expect(carbon.tier == .exactRecord)
        #expect(abs(carbon.low - carbon.value * 0.7) < 1e-9, "a name match carries ±30%")
        #expect(carbon.sources.first?.title.contains("matched by brand and name") == true)
        #expect(products.searches == 1 && products.lookups == 0)
    }

    @Test func onlyBrandedFoodWithoutABarcodeIsSearched() async throws {
        let products = CountingSearch([Self.record("Lays salt & vinegar", brand: "Lay's", gtin: "0060410010914")])
        let resolver = OpenFoodFactsResolver(products: products)
        let bag = Component(name: "Lay's Salt & Vinegar bag", category: .packaging, identifiers: Identifiers(brand: "Lay's"))
        #expect(try await resolver.resolve(request(bag)).metrics.isEmpty, "the record is the food's, not the bag's")
        let unbranded = Component(name: "Salt & vinegar chips", category: .food)
        #expect(try await resolver.resolve(request(unbranded)).metrics.isEmpty)
        let barcoded = Component(name: "Lay's Salt & Vinegar", category: .food,
                                 identifiers: Identifiers(gtin: "0000000000000", brand: "Lay's"))
        #expect(try await resolver.resolve(request(barcoded)).metrics.isEmpty, "a barcode is looked up, not searched")
        #expect(products.searches == 0 && products.lookups == 1)
    }

    @Test func aSearchThatFailsLeavesTheItemToTheLowerTiers() async throws {
        struct Down: ProductDatabase {
            func product(gtin: String) async throws -> ProductRecord? { nil }
            func searchProduct(brand: String, name: String) async throws -> ProductRecord? { throw GreenCoreError.timeout }
        }
        let chips = Component(name: "Lay's Classic", category: .food, identifiers: Identifiers(brand: "Lay's"))
        #expect(try await OpenFoodFactsResolver(products: Down()).resolve(request(chips)).metrics.isEmpty)
    }

    @Test func theScansAnsweredLookupsStillSearch() async throws {
        let products = CountingSearch([Self.record("Lays salt & vinegar", brand: "Lay's", gtin: "0060410010914")])
        let answered = AnsweredProducts(answers: ["5449000000996": .success(nil)], fallback: products)
        #expect(try await answered.searchProduct(brand: "Lay's", name: "Lay's Salt & Vinegar") != nil)
    }
}
