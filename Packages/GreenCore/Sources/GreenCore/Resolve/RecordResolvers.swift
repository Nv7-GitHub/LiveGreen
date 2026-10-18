/// T1: Open Food Facts by GTIN (spec §5.4) for food, drink, packaging and personal care, and for branded food without
/// a GTIN by a brand + name search that takes only a confident match (`ProductNameMatch`). For food, carbon and
/// packaging plastic are for the item's unit (`FoodServing.basis`): the whole pack when it is scored per pack, else
/// one serving; other items are taken as they are. OFF counts packaging only, so all of its plastic is packaging.
public struct OpenFoodFactsResolver: MetricResolver {
    public let tier = Tier.exactRecord
    public let name = "Open Food Facts"
    public let products: any ProductDatabase

    static let categories: Set<Category> = [.food, .packaging, .personalCare]

    public init(products: any ProductDatabase) {
        self.products = products
    }

    /// A record found by name is the product's own data, but its variant or recipe may differ from what was
    /// photographed, so its carbon carries ±30% (a barcode match ±20%) and says how it was found.
    static let nameMatchRelativeRange = 0.3

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let component = request.component
        guard Self.categories.contains(component.category) else { return .empty }
        let record: ProductRecord
        let matchedByName: Bool
        if let gtin = component.identifiers.gtin, !gtin.isEmpty {
            guard let found = try await products.product(gtin: gtin) else { return .empty }
            (record, matchedByName) = (found, false)
        } else if let found = await searched(component) {
            (record, matchedByName) = (found, true)
        } else {
            return .empty
        }
        var mass = component.quantities.massKg
        var share = 1.0
        if component.category == .food, case .pack(let pack) = FoodServing.basis(of: component) {
            // The record's packaging is for its own pack; a swap put on the original's pack size scales with it.
            mass = pack
            share = record.netMassKg.map { $0 > 0 ? pack / $0 : 1 } ?? 1
        } else if component.category == .food,
                  let serving = FoodServing.servingKg(component, recordServingKg: record.servingKg, recordNetKg: record.netMassKg) {
            mass = serving
            share = FoodServing.packageShare(servingKg: serving,
                                             packageKg: FoodServing.packageKg(component, recordNetKg: record.netMassKg))
        }
        var metrics = record.measuredMetrics(massKg: mass, packageShare: share).filter { request.metrics.contains($0.key) }
        if matchedByName, let carbon = metrics[.carbon] {
            let sources = carbon.sources.map { source in
                Source(title: "\(source.title) (matched by brand and name)", url: source.url, tier: source.tier,
                       quote: source.quote)
            }
            metrics[.carbon] = Measured(value: carbon.value, relativeRange: Self.nameMatchRelativeRange, unit: carbon.unit,
                                        tier: carbon.tier, sources: sources)
        }
        return ResolverOutput(metrics: metrics, stageShares: record.stageShares,
                              plasticPackagingShare: metrics[.plasticMass] == nil ? nil : 1)
    }

    /// Branded food without a barcode, looked up by brand and name. Packaging and personal care are not: the record
    /// would be the food's, not the wrapper's. A failed search just leaves the item to the lower tiers.
    func searched(_ component: Component) async -> ProductRecord? {
        guard component.category == .food, let brand = component.identifiers.brand?.trimmedNonEmpty else { return nil }
        return (try? await products.searchProduct(brand: brand, name: component.name)) ?? nil
    }
}

/// T1: ENERGY STAR certified records by brand + model number (spec §5.4) for electronics, which include
/// plugged-in appliances (household goods are unpowered).
public struct EnergyStarResolver: MetricResolver {
    public let tier = Tier.exactRecord
    public let name = "ENERGY STAR"
    public let appliances: any ApplianceDatabase

    public init(appliances: any ApplianceDatabase) {
        self.appliances = appliances
    }

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let component = request.component
        guard component.category == .electronic,
              let brand = component.identifiers.brand, !brand.isEmpty,
              let model = component.identifiers.model, !model.isEmpty else { return .empty }
        let record: ApplianceRecord? = if let client = appliances as? EnergyStarClient {
            try await client.appliance(brand: brand, model: model, deviceType: component.quantities.deviceType)
        } else {
            try await appliances.appliance(brand: brand, model: model)
        }
        guard let record else { return .empty }
        return ResolverOutput(metrics: record.measuredMetrics.filter { request.metrics.contains($0.key) })
    }
}
