import Foundation

extension ScanPipeline {
    /// Food scanned by barcode is scored per whole pack when its product record states the net quantity
    /// (`FoodServing.basis`); everything else stays as it is, so photographed meals, portions and packs of unknown
    /// size remain per serving. The records a barcode scan already fetched are reused; GTINs that identify or the
    /// labels gave a photo scan are looked up. Runs before the cache, whose entries are kept per basis.
    func onPackBasis(_ components: [Component], records: [ProductRecord]) async -> [Component] {
        let wanted = Set(components.filter { $0.category == .food }.compactMap(Self.normalizedGTIN))
        guard !wanted.isEmpty else { return components }
        var known: [String: ProductRecord] = [:]
        for record in records { known[GTINDigits.normalized(record.gtin) ?? record.gtin] = record }
        let products = products
        await withTaskGroup(of: (String, ProductRecord?).self) { group in
            for gtin in wanted.subtracting(known.keys) {
                // A failed lookup leaves the item per serving; the record resolver reports its own errors.
                group.addTask { (gtin, try? await products.product(gtin: gtin)) }
            }
            for await (gtin, record) in group { known[gtin] = record }
        }
        return components.map { component in
            guard component.category == .food, let gtin = Self.normalizedGTIN(component),
                  let record = known[gtin] else { return component }
            return Self.packed(component, record: record)
        }
    }

    /// The item scored per pack when the record states the pack's net quantity: the pack size and the label's
    /// serving go on the item, and identify's servings a week become the same food in packs a week. Without a
    /// servings guess the engine's default of one pack a week applies.
    static func packed(_ component: Component, record: ProductRecord) -> Component {
        guard component.quantities.packNetKg == nil, let net = record.netMassKg, net > 0 else { return component }
        var result = component
        if result.quantities.servingKg == nil { result.quantities.servingKg = record.servingKg }
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
