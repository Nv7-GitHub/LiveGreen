/// T1: Open Food Facts by GTIN (spec §5.4) for food, drink, packaging and personal care. Carbon is scaled to
/// one serving for food (per-unit convention on `ImpactEngine`), else to the item's mass.
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
        let q = component.quantities
        let mass = component.category == .food ? (q.servingKg ?? q.massKg) : q.massKg
        let metrics = record.measuredMetrics(massKg: mass).filter { request.metrics.contains($0.key) }
        return ResolverOutput(metrics: metrics, stageShares: record.stageShares)
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
