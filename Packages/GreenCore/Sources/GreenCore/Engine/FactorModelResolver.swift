/// T3: reference-table factors × the quantities from identification (spec §5.4). Values follow the
/// per-unit conventions documented on `ImpactEngine` (per serving or pack, per unit, or per item lifetime).
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
                              stageShares: output.stageShares, plasticPackagingShare: output.plasticPackagingShare)
    }

    // MARK: Food (per serving, or per pack for a barcoded pack of known size)

    func food(_ component: Component) -> ResolverOutput {
        var metrics: [MetricKey: Measured] = [:]
        var stages: [LifecycleStage: Double] = [:]
        let unitKg = FoodServing.unitKg(component)
        if let factor = store.foodFactor(group: FoodServing.factorKey(component)), let unitKg, unitKg > 0 {
            let sources = [factor.citation]
            // Coffee's factor is per kg of beans, so a brewed cup holds only its grounds' worth; the dry-commodity
            // factors (rice, pasta, pulses) count a cooked portion by its dry weight.
            let factorKg = unitKg * FoodServing.dryIngredientShare(group: factor.group, component: component)
                / FoodServing.cookedDivisor(group: factor.group, component: component)
            func perUnit(_ perKg: Double, _ unit: MetricUnit) -> Measured {
                FactorRanges.multiplicative(perKg * factorKg, factor: 1.6, unit: unit, sources: sources)
            }
            metrics[.carbon] = perUnit(factor.kgCO2ePerKg, .kgCO2e)
            metrics[.water] = perUnit(factor.litersPerKg, .liters)
            metrics[.land] = perUnit(factor.landM2YearPerKg, .squareMeterYears)
            metrics[.waterPollution] = perUnit(factor.gPO4ePerKg, .gramsPO4e)
            stages = factor.stageShares
        }
        var packagingShare: Double?
        if let blend = packagingBlend(component) {
            // The packaging is the whole pack's; one serving carries its share of the plastic, a pack all of it. A swap's
            // packaging is already on the original's pack size (`Alternative.onBasis`), as OFF records are scaled.
            var endOfLife = blend.endOfLifeMetrics()
            let share = unitKg.map { FoodServing.packageShare(servingKg: $0, packageKg: FoodServing.packageKg(component)) } ?? 1
            endOfLife[.plasticMass] = endOfLife[.plasticMass]?.scaled(by: share)
            metrics.merge(endOfLife) { current, _ in current }
            packagingShare = 1
        } else if !FoodServing.isPackaged(component) {
            // Unpackaged food leaves no plastic. It gets no recyclability or decomposition time either: the food is
            // eaten, and composting scraps is not recycling. A barcoded item whose packaging is unknown is not
            // unpackaged, so it gets no plastic figure here rather than a false zero.
            let source = Source(title: "Unpackaged food: no packaging pictured", tier: .factorModel)
            metrics[.plasticMass] = Measured.exact(0, unit: .grams, tier: .factorModel, sources: [source])
        }
        return ResolverOutput(metrics: metrics, stageShares: stages, plasticPackagingShare: packagingShare)
    }

    // MARK: Packaging and personal care (per unit)

    func packaging(_ component: Component) -> ResolverOutput {
        guard let blend = packagingBlend(component) else { return .empty }
        var metrics = blend.endOfLifeMetrics()
        metrics[.carbon] = FactorRanges.relative(blend.kgCO2e, 0.35, unit: .kgCO2e, sources: blend.sources)
        metrics[.water] = FactorRanges.relative(blend.liters, 0.5, unit: .liters, sources: blend.sources)
        return ResolverOutput(metrics: metrics, stageShares: StageModel.defaultCarbonShares(for: .packaging),
                              plasticPackagingShare: 1)
    }

    /// Only the container is modeled; the product's own footprint is left to records or estimates.
    func personalCare(_ component: Component) -> ResolverOutput {
        guard let blend = packagingBlend(component) else { return .empty }
        return ResolverOutput(metrics: blend.endOfLifeMetrics(), plasticPackagingShare: 1)
    }

    /// A packaging item is its own materials and may give either mass. Anything else (food, drinks, personal care,
    /// household refills) carries its packaging in `packagingMassG`, since `massKg` includes the contents. That
    /// packaging is identify's `packagingMaterials`; else the item's own materials without what is used up (food, a
    /// formula), which older answers gave for the whole pack; else plastic of unknown kind. The food's own split
    /// (96% food, 4% film) is never applied to the package.
    func packagingBlend(_ component: Component) -> MaterialBlend? {
        let q = component.quantities, ids = component.identifiers
        if component.category == .packaging {
            return MaterialBlend(materials: discarded(ids.materials), massG: q.packagingMassG ?? q.massKg.map { $0 * 1000 } ?? 0,
                                 store: store)
        }
        guard let massG = q.packagingMassG, massG > 0 else { return nil }
        let candidates = [discarded(ids.packagingMaterials ?? []), discarded(ids.materials), Self.unknownPackaging]
        return candidates.lazy.compactMap { MaterialBlend(materials: $0, massG: massG, store: self.store) }.first
    }

    /// Packaging whose materials nobody reported.
    static let unknownPackaging = [MaterialShare(material: "other_plastic", percent: 100)]

    /// The materials that are thrown away rather than used up.
    func discarded(_ materials: [MaterialShare]) -> [MaterialShare] {
        materials.filter { store.materialFactor(material: $0.material)?.isConsumed != true }
    }

    /// Outside food, a product's own liquid tagged as food (`food_organic`) is its formula: food has no production
    /// footprint here and would make a cleaner read as compost.
    func outsideFood(_ materials: [MaterialShare]) -> [MaterialShare] {
        materials.map { share in
            store.materialFactor(material: share.material)?.endOfLife.material == "food_organic"
                ? MaterialShare(material: "detergent_formula", percent: share.percent) : share
        }
    }
}
