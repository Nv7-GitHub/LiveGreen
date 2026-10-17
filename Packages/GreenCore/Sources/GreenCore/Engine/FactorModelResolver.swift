/// T3: reference-table factors × the quantities from identification (spec §5.4). Values follow the
/// per-unit conventions documented on `ImpactEngine` (per serving, per unit, or per item lifetime).
public struct FactorModelResolver: MetricResolver {
    public let tier = Tier.factorModel
    public let name = "Reference factor model"
    public let store: ReferenceStore
    public let engine: ImpactEngine

    public init(store: ReferenceStore = .bundled) {
        self.store = store
        self.engine = ImpactEngine(reference: store)
    }

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let output: ResolverOutput = switch request.component.category {
        case .food: food(request.component)
        case .electronic: electronic(request.component, profile: request.profile)
        case .clothing: clothing(request.component)
        case .packaging: packaging(request.component)
        case .household: household(request.component)
        case .personalCare: personalCare(request.component)
        }
        return ResolverOutput(metrics: output.metrics.filter { request.metrics.contains($0.key) },
                              stageShares: output.stageShares)
    }

    // MARK: Food (per serving)

    func food(_ component: Component) -> ResolverOutput {
        let q = component.quantities
        var metrics: [MetricKey: Measured] = [:]
        var stages: [LifecycleStage: Double] = [:]
        if let factor = store.foodFactor(group: q.foodGroup ?? component.name),
           let servingKg = q.servingKg ?? q.massKg ?? q.volumeLiters, servingKg > 0 {
            let sources = [factor.citation]
            func perServing(_ perKg: Double, _ unit: MetricUnit) -> Measured {
                FactorRanges.multiplicative(perKg * servingKg, factor: 1.6, unit: unit, sources: sources)
            }
            metrics[.carbon] = perServing(factor.kgCO2ePerKg, .kgCO2e)
            metrics[.water] = perServing(factor.litersPerKg, .liters)
            metrics[.land] = perServing(factor.landM2YearPerKg, .squareMeterYears)
            metrics[.waterPollution] = perServing(factor.gPO4ePerKg, .gramsPO4e)
            stages = factor.stageShares
        }
        if let blend = packagingBlend(component) {
            metrics.merge(blend.endOfLifeMetrics()) { current, _ in current }
        } else if component.identifiers.materials.isEmpty, (q.packagingMassG ?? 0) == 0,
                  let organic = store.materialFactor(material: "food_organic") {
            // Unpackaged food: only the food itself is left at end of life.
            let sources = [organic.citation]
            metrics[.plasticMass] = Measured.exact(0, unit: .grams, tier: .factorModel, sources: sources)
            metrics[.recyclablePercent] = FactorRanges.percent(organic.endOfLife.recyclablePercent, spread: 5, sources: sources)
            metrics[.decompositionTime] = FactorRanges.multiplicative(organic.endOfLife.decompositionYears, factor: 2,
                                                                      unit: .years, sources: sources)
        }
        return ResolverOutput(metrics: metrics, stageShares: stages)
    }

    // MARK: Packaging and personal care (per unit)

    func packaging(_ component: Component) -> ResolverOutput {
        guard let blend = packagingBlend(component) else { return .empty }
        var metrics = blend.endOfLifeMetrics()
        metrics[.carbon] = FactorRanges.relative(blend.kgCO2e, 0.35, unit: .kgCO2e, sources: blend.sources)
        metrics[.water] = FactorRanges.relative(blend.liters, 0.5, unit: .liters, sources: blend.sources)
        return ResolverOutput(metrics: metrics, stageShares: StageModel.defaultCarbonShares(for: .packaging))
    }

    /// Only the container is modeled; the product's own footprint is left to records or estimates.
    func personalCare(_ component: Component) -> ResolverOutput {
        guard let blend = packagingBlend(component) else { return .empty }
        return ResolverOutput(metrics: blend.endOfLifeMetrics())
    }

    /// Packaging items may give either mass; for food and personal care `massKg` includes the contents,
    /// so only an explicit packaging mass counts.
    func packagingBlend(_ component: Component) -> MaterialBlend? {
        let q = component.quantities
        let mass = component.category == .packaging ? (q.packagingMassG ?? q.massKg.map { $0 * 1000 }) : q.packagingMassG
        return MaterialBlend(materials: component.identifiers.materials, massG: mass ?? 0, store: store)
    }
}
