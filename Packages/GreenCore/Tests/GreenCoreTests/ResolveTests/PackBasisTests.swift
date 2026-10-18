import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

/// Food scanned by barcode with its net quantity on record is scored per whole pack; everything else stays per
/// serving (spec §5.6, `FoodServing.basis`).
@Suite("Per-pack basis for barcoded food")
struct PackBasisTests {
    /// A 340 g bag: 2.5 kg CO2e per kg, 28 g servings, 12 g of plastic film.
    private static let chips = ProductRecord(
        gtin: "0028400090858", name: "Tortilla chips 340 g", brand: "Acme", category: .food, netMassKg: 0.34,
        servingKg: 0.028, carbonKgPerKg: 2.5,
        packaging: [PackagingPart(material: "plastic film", massG: 12, isPlastic: true, recyclable: false)],
        sourceURL: URL(string: "https://world.openfoodfacts.org/product/0028400090858")!, foodGroup: "maize")

    private static var unsized: ProductRecord {
        var record = chips
        record.netMassKg = nil
        return record
    }

    private func pipeline(_ records: [ProductRecord], scene: DemoScene = .deskSetup,
                          cache: (any ResolutionCache)? = nil, products: (any ProductDatabase)? = nil) -> ScanPipeline {
        let store = ReferenceStore.bundled
        let products = products
            ?? FakeProductDatabase(records: Dictionary(uniqueKeysWithValues: records.map { ($0.gtin, $0) }))
        let ladder = EvidenceLadder(resolvers: [OpenFoodFactsResolver(products: products), FactorModelResolver(store: store),
                                                EstimateResolver()], cache: cache)
        return ScanPipeline(vision: FakeVisionIdentifier(scene: scene), alternatives: FakeAlternativeSuggester(),
                            products: products, ladder: ladder, engine: ImpactEngine(reference: store), profile: .default)
    }

    private func barcodeScan(_ record: ProductRecord, cache: (any ResolutionCache)? = nil) async throws -> ScanResult {
        try await pipeline([record], cache: cache).run(image: Data(), hints: OCRHints(gtins: [record.gtin]), mode: .barcode)
    }

    @Test func barcodeWithNetQuantityIsScoredPerPack() async throws {
        let scan = try await barcodeScan(Self.chips)
        let bag = try #require(scan.components.first)
        #expect(FoodServing.basis(of: bag) == .pack(kg: 0.34))
        // Per-kg × net mass, and all of the pack's plastic rather than one serving's share.
        let carbon = try #require(bag.metrics[.carbon])
        #expect(abs(carbon.value - 2.5 * 0.34) < 1e-9)
        #expect(try #require(bag.metrics[.plasticMass]).value == 12)
        #expect(bag.plasticPackagingShare == 1)
        #expect(try #require(bag.metrics[.water]).value > 0)

        // A year is packs a week × 52 × the pack. With no rate stated, the default one serving a week is given in
        // packs, so the year counts the same food as per serving did, not a whole pack a week.
        let engine = ImpactEngine()
        #expect(engine.editableUsage(for: bag).map(\.field) == [.packsPerWeek])
        #expect(abs((engine.editableUsage(for: bag).first?.value ?? 0) - 0.028 / 0.34) < 1e-9)
        let yearly = try #require(engine.yearly(.carbon, of: bag))
        #expect(abs(yearly.value - 1 * 52 * 2.5 * 0.028) < 1e-9)
        #expect(abs(try #require(scan.yearlyTotals[.carbon]).value - yearly.value) < 1e-9)
        #expect(abs(try #require(engine.yearly(.plasticMass, of: bag)).value - 52 * 12 * 0.028 / 0.34) < 1e-9)

        let twice = engine.applyingAnswer(AnswerOption(label: "2", field: .packsPerWeek, value: 2), to: bag, profile: .default)
        #expect(abs(try #require(engine.yearly(.carbon, of: twice)).value - 2 * 52 * 2.5 * 0.34) < 1e-9)
        #expect(abs(try #require(engine.yearly(.plasticMass, of: twice)).value - 2 * 52 * 12) < 1e-9)
    }

    @Test func barcodeWithoutNetQuantityStaysPerServing() async throws {
        let scan = try await barcodeScan(Self.unsized)
        let bag = try #require(scan.components.first)
        #expect(bag.quantities.packNetKg == nil)
        #expect(FoodServing.basis(of: bag) == .serving(kg: 0.028))
        #expect(abs(try #require(bag.metrics[.carbon]).value - 2.5 * 0.028) < 1e-9)
        // Without a pack size the plastic cannot be shared out, so the record's figure stands, as before.
        #expect(try #require(bag.metrics[.plasticMass]).value == 12)
        let engine = ImpactEngine()
        #expect(engine.editableUsage(for: bag).map(\.field) == [.servingsPerWeek])
        let yearly = try #require(engine.yearly(.carbon, of: bag))
        #expect(abs(yearly.value - 1 * 52 * 2.5 * 0.028) < 1e-9)
    }

    @Test func photographedPackWithARecordedGTINIsPerPackAtTheSameFoodPerWeek() async throws {
        // The lunch scene's cola can carries a GTIN from identify; the demo record says 330 mL net.
        let scan = try await pipeline(Array(FakeProductDatabase.defaultRecords.values), scene: .meal)
            .run(image: Data([1]), hints: .none, mode: .photo)
        let can = try #require(scan.components.first { $0.name == "Cola can" })
        #expect(FoodServing.basis(of: can) == .pack(kg: 0.33))
        #expect(abs(try #require(can.metrics[.carbon]).value - 0.47 * 0.33) < 1e-9)
        // Identify's 3 servings a week of a one-serving can are 3 cans a week.
        #expect(can.usage?.packsPerWeek == 3)
        // Plated food in the same photo stays per serving.
        let burger = try #require(scan.components.first { $0.name == "Beef burger" })
        #expect(FoodServing.basis(of: burger) == .serving(kg: 0.12))
        #expect(ImpactEngine().editableUsage(for: burger).map(\.field) == [.servingsPerWeek])
    }

    @Test func servingsAnswersBecomePacksForAPerPackItem() throws {
        var bag = Component(name: "Chips", category: .food, identifiers: Identifiers(gtin: Self.chips.gtin),
                            quantities: Quantities(servingKg: 0.034, packNetKg: 0.34))
        bag.metrics[.carbon] = .exact(0.85, unit: .kgCO2e, tier: .exactRecord)
        let engine = ImpactEngine()
        let answered = engine.applyingAnswer(AnswerOption(label: "Most days", field: .servingsPerWeek, value: 5),
                                             to: bag, profile: .default)
        // 5 servings of 34 g are half a 340 g pack.
        #expect(abs((answered.usage?.packsPerWeek ?? 0) - 0.5) < 1e-9)
        #expect(abs(try #require(engine.yearly(.carbon, of: answered)).value - 0.5 * 52 * 0.85) < 1e-9)
    }

    @Test func estimatesAndFactorsCoverTheWholePack() throws {
        let identified = Component(name: "Rice", category: .food,
                                   identifiers: Identifiers(gtin: "0000000000017",
                                                            materials: [MaterialShare(material: "pp", percent: 100)]),
                                   quantities: Quantities(servingKg: 0.1, packagingMassG: 30, foodGroup: "rice", packNetKg: 1.0),
                                   fallbackEstimates: [.carbon: EstimateRange(value: 0.4, low: 0.3, high: 0.5),
                                                       .recyclablePercent: EstimateRange(value: 20, low: 10, high: 30)])
        #expect(FoodServing.servingsPerPack(identified) == 10)
        let factor = FactorModelResolver(store: .bundled).food(identified)
        let perServing = FactorModelResolver(store: .bundled).food(FoodServing.servingView(of: identified))
        #expect(abs(try #require(factor.metrics[.carbon]).value - 10 * perServing.metrics[.carbon]!.value) < 1e-9)
        #expect(abs(try #require(factor.metrics[.plasticMass]).value - 30) < 1e-9)
        #expect(abs(try #require(perServing.metrics[.plasticMass]).value - 3) < 1e-9)
    }

    @Test func estimatesPerServingAreScaledToThePack() async throws {
        let bag = Component(name: "Rice", category: .food, identifiers: Identifiers(gtin: "0000000000017"),
                            quantities: Quantities(servingKg: 0.1, packNetKg: 1.0),
                            fallbackEstimates: [.carbon: EstimateRange(value: 0.4, low: 0.3, high: 0.5),
                                                .recyclablePercent: EstimateRange(value: 20, low: 10, high: 30)])
        let output = try await EstimateResolver().resolve(
            ResolutionRequest(component: bag, metrics: [.carbon, .recyclablePercent], profile: .default))
        #expect(abs(try #require(output.metrics[.carbon]).value - 4) < 1e-9)
        #expect(output.metrics[.recyclablePercent]?.value == 20)
    }

    @Test func plasticEstimatesAreForThePackageAlready() async throws {
        // A 200 g bag of 28 g servings: carbon per serving is scaled up, the package's 4 g of plastic is not.
        let bag = Component(name: "Chips", category: .food, identifiers: Identifiers(gtin: "0000000000017"),
                            quantities: Quantities(servingKg: 0.028, packNetKg: 0.2),
                            fallbackEstimates: [.carbon: EstimateRange(value: 0.05, low: 0.04, high: 0.06),
                                                .plasticMass: EstimateRange(value: 4, low: 2, high: 6)])
        let output = try await EstimateResolver().resolve(
            ResolutionRequest(component: bag, metrics: [.carbon, .plasticMass], profile: .default))
        #expect(abs(try #require(output.metrics[.carbon]).value - 0.05 * 0.2 / 0.028) < 1e-9)
        #expect(output.metrics[.plasticMass]?.value == 4)
        // The identify prompt says which basis each estimate is on.
        let prompt = ClaudeClient.identifySystemPrompt(vocabulary: .default)
        #expect(prompt.contains("are for ONE serving (serving_kg), even when a whole pack is pictured"))
        #expect(prompt.contains("`plasticMass` is all the plastic in the package pictured"))
    }

    @Test func aSwapWithoutAServingIsScaledByTheOriginalsServings() async throws {
        // The suggester's estimates are per 28 g serving of the original; the swap gives no serving of its own.
        let original = Component(name: "Chips", category: .food, identifiers: Identifiers(gtin: "0000000000017"),
                                 quantities: Quantities(servingKg: 0.028, packNetKg: 0.2))
        let swap = Alternative(name: "Lentil chips", category: .food, quantities: Quantities(massKg: 0.2),
                               rationale: "", fallbackEstimates: [.carbon: EstimateRange(value: 0.03, low: 0.02, high: 0.04)])
            .onBasis(of: original)
        #expect(swap.quantities.servingKg == 0.028)
        let asComponent = Component(name: swap.name, category: .food, quantities: swap.quantities,
                                    fallbackEstimates: swap.fallbackEstimates)
        #expect(abs(FoodServing.servingsPerPack(asComponent) - FoodServing.servingsPerPack(original)) < 1e-9)
        let output = try await EstimateResolver().resolve(
            ResolutionRequest(component: asComponent, metrics: [.carbon], profile: .default))
        #expect(abs(try #require(output.metrics[.carbon]).value - 0.03 * 0.2 / 0.028) < 1e-9)
    }

    @Test func aSwapsPackagingIsPutOnTheOriginalsPackSize() throws {
        // A 400 g swap pack with 20 g of film, compared on the original's 200 g pack: half the film, as OFF scales.
        let original = Component(name: "Rice", category: .food, identifiers: Identifiers(gtin: "0000000000017"),
                                 quantities: Quantities(servingKg: 0.1, packNetKg: 0.2))
        let film = [MaterialShare(material: "pp", percent: 100)]
        let swap = Alternative(name: "Lentils", category: .food, identifiers: Identifiers(materials: film),
                               quantities: Quantities(massKg: 0.4, servingKg: 0.1, packagingMassG: 20, foodGroup: "pulses"),
                               rationale: "", fallbackEstimates: [.plasticMass: EstimateRange(value: 20, low: 10, high: 30)])
        let onBasis = swap.onBasis(of: original)
        #expect(onBasis.quantities.packagingMassG == 10)
        #expect(onBasis.fallbackEstimates[.plasticMass]?.value == 10)
        let resolver = FactorModelResolver(store: .bundled)
        let ownPack = Component(name: swap.name, category: .food, identifiers: swap.identifiers,
                                quantities: Quantities(servingKg: 0.1, packagingMassG: 20, foodGroup: "pulses", packNetKg: 0.4))
        let onOriginal = Component(name: swap.name, category: .food, identifiers: swap.identifiers,
                                   quantities: onBasis.quantities)
        let own = try #require(resolver.food(ownPack).metrics[.plasticMass]).value
        #expect(own > 0)
        #expect(abs(try #require(resolver.food(onOriginal).metrics[.plasticMass]).value - own / 2) < 1e-9)
    }

    @Test func aPerServingCacheEntryIsAMissForThePack() async throws {
        let cache = InMemoryResolutionCache()
        await cache.store(CachedResolution(metrics: [.carbon: .exact(0.07, unit: .kgCO2e, tier: .exactRecord)],
                                           category: .food), forKey: "gtin:\(Self.chips.gtin)")
        let bag = try #require(try await barcodeScan(Self.chips, cache: cache).components.first)
        #expect(abs(try #require(bag.metrics[.carbon]).value - 2.5 * 0.34) < 1e-9)
        // The per-pack numbers replace the old entry, so a rescan reads them back.
        let again = try #require(try await barcodeScan(Self.chips, cache: cache).components.first)
        #expect(again.metrics == bag.metrics)
    }

    @Test func aPhotoScanLooksEachGTINUpOnce() async throws {
        // The pack basis needs the cola can's record before the cache; T1 reuses it rather than asking again.
        let products = CountingProducts(Array(FakeProductDatabase.defaultRecords.values))
        let scan = try await pipeline([], scene: .meal, products: products).run(image: Data([1]), hints: .none, mode: .photo)
        let can = try #require(scan.components.first { $0.name == "Cola can" })
        #expect(FoodServing.basis(of: can) == .pack(kg: 0.33))
        #expect(can.metrics[.carbon]?.tier == .exactRecord)
        #expect(products.lookups == 1)
    }

    @Test func aCachedPackNeedsNoLookupAndAFailedOneIsNotCached() async throws {
        let cache = InMemoryResolutionCache()
        let records = Array(FakeProductDatabase.defaultRecords.values)
        let online = try await pipeline([], scene: .meal, cache: cache, products: CountingProducts(records))
            .run(image: Data([1]), hints: .none, mode: .photo)
        let can = try #require(online.components.first { $0.name == "Cola can" })

        // Offline, the cache entry gives the basis, so the rescan is a hit with the same numbers and no lookup.
        let offline = CountingProducts(records, failing: true)
        let rescan = try await pipeline([], scene: .meal, cache: cache, products: offline)
            .run(image: Data([1]), hints: .none, mode: .photo)
        let cached = try #require(rescan.components.first { $0.name == "Cola can" })
        #expect(cached.quantities.packNetKg == 0.33)
        #expect(cached.usage?.packsPerWeek == can.usage?.packsPerWeek)
        #expect(cached.metrics == can.metrics)
        #expect(offline.lookups == 0)

        // Offline with nothing cached, the can stays per serving and is not remembered, so the per-serving numbers
        // never stand in for the pack's; its one failed lookup is not repeated by T1.
        let empty = InMemoryResolutionCache()
        let failed = CountingProducts(records, failing: true)
        let unchecked = try await pipeline([], scene: .meal, cache: empty, products: failed)
            .run(image: Data([1]), hints: .none, mode: .photo)
        let perServing = try #require(unchecked.components.first { $0.name == "Cola can" })
        #expect(perServing.quantities.packNetKg == nil)
        #expect(await empty.cachedResolution(forKey: "gtin:5449000000996") == nil)
        #expect(failed.lookups == 1)
    }

    @Test func swapsForAPackCoverTheSameFoodAtTheSameRate() async throws {
        let pipeline = pipeline([Self.chips])
        var scan = try await pipeline.run(image: Data(), hints: OCRHints(gtins: [Self.chips.gtin]), mode: .barcode)
        scan = pipeline.applying([(scan.components[0].id, AnswerOption(label: "2", field: .packsPerWeek, value: 2))], to: scan)
        let bag = try #require(try await pipeline.suggestAlternatives(for: scan).components.first)
        let swap = try #require(bag.alternatives.first)
        #expect(swap.quantities.packNetKg == 0.34)
        #expect(swap.usage?.packsPerWeek == 2)
        // The suggester's per-serving estimate (60% of a serving's carbon) is scaled back up to a 340 g pack.
        let carbon = try #require(swap.metrics[.carbon])
        #expect(abs(carbon.value - 0.6 * 2.5 * 0.34) < 1e-6)
        let values = try #require(GreenScore.comparison(.carbon, original: bag, alternative: swap, engine: ImpactEngine()))
        #expect(abs(values.current.value - 2 * 52 * 2.5 * 0.34) < 1e-9)
        #expect(abs(values.swap.value - 2 * 52 * carbon.value) < 1e-9)
    }

    @Test func swapSuggestersSeeOneServing() throws {
        var bag = Component(name: "Chips", category: .food, quantities: Quantities(servingKg: 0.034, packNetKg: 0.34),
                            usage: UsageProfile(packsPerWeek: 0.5))
        bag.metrics = [.carbon: .exact(0.85, unit: .kgCO2e, tier: .exactRecord),
                       .recyclablePercent: .exact(40, unit: .percent, tier: .exactRecord)]
        bag.metrics[.plasticMass] = .exact(12, unit: .grams, tier: .exactRecord)
        let view = FoodServing.servingView(of: bag)
        #expect(view.quantities.packNetKg == nil)
        #expect(abs(try #require(view.metrics[.carbon]).value - 0.085) < 1e-9)
        // Plastic is the package's whatever the basis, as the prompts define it.
        #expect(view.metrics[.plasticMass]?.value == 12)
        #expect(view.metrics[.recyclablePercent]?.value == 40)
        #expect(view.usage?.servingsPerWeek == 5)
        #expect(view.usage?.packsPerWeek == nil)
    }

    @Test func savedScansAndCacheEntriesWithoutABasisDecodePerServing() throws {
        let quantities = try JSONDecoder().decode(Quantities.self, from: Data(#"{"massKg":0.34,"servingKg":0.028}"#.utf8))
        #expect(quantities.packNetKg == nil)
        let usage = try JSONDecoder().decode(UsageProfile.self, from: Data(#"{"servingsPerWeek":3}"#.utf8))
        #expect(usage.packsPerWeek == nil)
        let entry = try JSONDecoder().decode(CachedResolution.self, from: Data(#"{"metrics":{},"stageShares":{}}"#.utf8))
        #expect(entry.packNetKg == nil)
        let saved = Component(name: "Chips", category: .food, identifiers: Identifiers(gtin: Self.chips.gtin),
                              quantities: quantities)
        #expect(FoodServing.basis(of: saved) == .serving(kg: 0.028))
        #expect(!UsageField.askable.contains(.packsPerWeek))
    }
}

/// Product lookups counted, and all failing when `failing`, as Open Food Facts does offline.
final class CountingProducts: ProductDatabase, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let records: [String: ProductRecord]
    private let failing: Bool
    var lookups: Int { lock.withLock { count } }

    init(_ records: [ProductRecord], failing: Bool = false) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.gtin, $0) })
        self.failing = failing
    }

    func product(gtin: String) async throws -> ProductRecord? {
        lock.withLock { count += 1 }
        if failing { throw GreenCoreError.timeout }
        return records[gtin]
    }
}
