/// T1: Open Food Facts by GTIN (spec §5.4) for food, drink, packaging and personal care. For food, carbon and
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

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let component = request.component
        guard Self.categories.contains(component.category),
              let gtin = component.identifiers.gtin, !gtin.isEmpty,
              let record = try await products.product(gtin: gtin) else { return .empty }
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
        let metrics = record.measuredMetrics(massKg: mass, packageShare: share).filter { request.metrics.contains($0.key) }
        return ResolverOutput(metrics: metrics, stageShares: record.stageShares,
                              plasticPackagingShare: metrics[.plasticMass] == nil ? nil : 1)
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
