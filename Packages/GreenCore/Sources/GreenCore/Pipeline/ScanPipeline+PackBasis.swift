import Foundation

extension ScanPipeline {
    /// One scan's items on their food basis, with what was learned on the way.
    struct PackBasis: Sendable {
        var components: [Component]
        /// Open Food Facts answers by normalized GTIN (a record, nil for an unknown product, or the lookup's error),
        /// which T1 reuses instead of asking again (`EvidenceLadder.reusing`).
        var answers: [String: Result<ProductRecord?, any Error>] = [:]
        /// Items whose lookup failed, so their basis is unknown. They stay per serving and are not cached, so a later
        /// scan with a connection can still put them on their pack.
        var unchecked: Set<UUID> = []
    }

    /// Food scanned by barcode is scored per whole pack when its product record states the net quantity
    /// (`FoodServing.basis`); everything else stays as it is, so photographed meals, portions and packs of unknown
    /// size remain per serving. The basis comes from the records a barcode scan already fetched, else from the item's
    /// cache entry (so a cache hit needs no network), else from one lookup per GTIN, the one T1 would make anyway.
    /// Runs before the cache, whose entries are kept per basis.
    func onPackBasis(_ components: [Component], records: [ProductRecord]) async -> PackBasis {
        var basis = PackBasis(components: components)
        for record in records { basis.answers[GTINDigits.normalized(record.gtin) ?? record.gtin] = .success(record) }
        var pending: [Int] = []
        for (index, component) in components.enumerated() where component.category == .food {
            guard let gtin = Self.normalizedGTIN(component) else { continue }
            if case .success(let record?) = basis.answers[gtin] {
                basis.components[index] = Self.packed(component, netKg: record.netMassKg, servingKg: record.servingKg)
            } else if let entry = await cachedEntry(for: component) {
                basis.components[index] = Self.packed(component, netKg: entry.packNetKg, servingKg: entry.servingKg)
            } else {
                pending.append(index)
            }
        }
        let lookups = Set(pending.compactMap { Self.normalizedGTIN(components[$0]) })
        let products = products
        await withTaskGroup(of: (String, Result<ProductRecord?, any Error>).self) { group in
            for gtin in lookups {
                group.addTask {
                    do { return (gtin, .success(try await products.product(gtin: gtin))) } catch { return (gtin, .failure(error)) }
                }
            }
            for await (gtin, answer) in group { basis.answers[gtin] = answer }
        }
        for index in pending {
            let component = components[index]
            switch Self.normalizedGTIN(component).flatMap({ basis.answers[$0] }) {
            case .success(let record?):
                basis.components[index] = Self.packed(component, netKg: record.netMassKg, servingKg: record.servingKg)
            case .failure: basis.unchecked.insert(component.id)
            default: break
            }
        }
        return basis
    }

    /// The item's cache entry when it would be a hit: its `packNetKg` is the basis it was resolved on.
    private func cachedEntry(for component: Component) async -> CachedResolution? {
        guard let cache = ladder.cache, let key = component.resolutionKey,
              let entry = await cache.cachedResolution(forKey: key), entry.metrics[.carbon] != nil else { return nil }
        return entry
    }

    /// The item scored per pack when the net quantity is known: the pack size and the label's serving go on the item,
    /// and identify's servings a week become the same food in packs a week. Without a servings guess the engine's
    /// default servings a week, in packs, applies (`FoodServing.packsPerWeek(of:)`).
    static func packed(_ component: Component, netKg: Double?, servingKg: Double?) -> Component {
        guard component.quantities.packNetKg == nil, let net = netKg, net > 0 else { return component }
        var result = component
        if result.quantities.servingKg == nil { result.quantities.servingKg = servingKg }
        result.quantities.packNetKg = net
        if var usage = result.usage, usage.packsPerWeek == nil, let servings = usage.servingsPerWeek {
            usage.packsPerWeek = FoodServing.packsPerWeek(servingsPerWeek: servings, for: result)
            result.usage = usage
        }
        return result
    }

    private static func normalizedGTIN(_ component: Component) -> String? {
        component.identifiers.gtin.flatMap(GTINDigits.normalized)
    }
}

extension EvidenceLadder {
    /// The ladder with its Open Food Facts resolvers answering first from what this scan already asked, so a GTIN is
    /// looked up at most once per scan.
    func reusing(_ answers: [String: Result<ProductRecord?, any Error>]) -> EvidenceLadder {
        guard !answers.isEmpty else { return self }
        return EvidenceLadder(resolvers: resolvers.map { resolver in
            guard let records = resolver as? OpenFoodFactsResolver else { return resolver }
            return OpenFoodFactsResolver(products: AnsweredProducts(answers: answers, fallback: records.products))
        }, cache: cache)
    }
}

/// Product lookups answered from one scan's earlier answers (failures included, so T1 does not wait on them twice);
/// other GTINs go to `fallback`.
struct AnsweredProducts: ProductDatabase {
    let answers: [String: Result<ProductRecord?, any Error>]
    let fallback: any ProductDatabase

    func product(gtin: String) async throws -> ProductRecord? {
        if let answer = GTINDigits.normalized(gtin).flatMap({ answers[$0] }) { return try answer.get() }
        return try await fallback.product(gtin: gtin)
    }

    func searchProduct(brand: String, name: String) async throws -> ProductRecord? {
        try await fallback.searchProduct(brand: brand, name: name)
    }

    func productImage(for record: ProductRecord) async -> Data? {
        await fallback.productImage(for: record)
    }
}
