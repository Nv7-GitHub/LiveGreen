import Foundation

extension ScanPipeline {
    /// Spec-sheet PCFs (T2) and model estimates (T4) report electronics carbon without use-phase electricity
    /// (the prompts ask for that), so the use phase is added here: lifetime carbon = embodied + yearly kWh ×
    /// grid × lifespan, the same formula as the factor model. Records (T1) and factor models (T3) already
    /// include it. A vehicle's researched or estimated carbon is its production likewise (the prompts ask for that),
    /// and gets its driving added by the vehicle model.
    func addingUsePhase(to component: Component) -> Component {
        if let vehicle = engine.vehicleModel(for: component) {
            guard let production = component.metrics[.carbon],
                  production.tier == .researchedSpec || production.tier == .estimate else { return component }
            var result = component
            let lifetime = engine.vehicleLifetimeCarbon(production: production, of: component, model: vehicle, profile: profile)
            result.metrics[.carbon] = lifetime.carbon
            result.stageShares = lifetime.stages
            return result
        }
        guard component.category == .electronic, let embodied = component.metrics[.carbon],
              embodied.tier == .researchedSpec || embodied.tier == .estimate,
              let kWh = component.metrics[.yearlyElectricity] else { return component }
        let lifespan = engine.lifespan(of: component)
        let grid = engine.gridMeasured(for: profile)
        let lifetime = MonteCarlo(seed: component.stableSeed).propagate([embodied, kWh, grid, lifespan], unit: .kgCO2e,
                                                                        salt: "use-phase.carbon") {
            ImpactEngine.lifetimeCarbon(embodiedKg: $0[0], lifespanYears: $0[3],
                                        annualUseKg: ImpactEngine.useCarbon(kWh: $0[1], gramsPerKWh: $0[2]))
        }
        var result = component
        result.metrics[.carbon] = Measured(value: lifetime.value, low: lifetime.low, high: lifetime.high, unit: .kgCO2e,
                                           tier: max(embodied.tier, kWh.tier), sources: lifetime.sources)

        // The recorded split (if any) describes embodied carbon; a use share in it came from another resolver.
        var embodiedShares = StageModel.normalized(component.stageShares.filter { $0.key != .use })
        if embodiedShares.isEmpty {
            embodiedShares = StageModel.normalized(StageModel.defaultCarbonShares(for: .electronic).filter { $0.key != .use })
        }
        var absolute = embodiedShares.mapValues { $0 * embodied.value }
        absolute[.use, default: 0] += max(lifetime.value - embodied.value, 0)
        result.stageShares = StageModel.normalized(absolute)
        return result
    }
}
