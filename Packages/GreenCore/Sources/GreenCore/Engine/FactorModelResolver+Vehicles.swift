import Foundation

extension FactorModelResolver {
    // MARK: Vehicles (per vehicle lifetime, driving included)

    /// Production from the glider and battery, driving at the user's distance (or the national average) and grid,
    /// a 15-year life, plastics from the reported materials (else a typical share of the curb mass) and the
    /// end-of-life vehicle recycling rate. Vehicles are shredded for scrap, so there is no decomposition time and no
    /// household-style water figure.
    func vehicle(_ component: Component, profile: UserProfile) -> ResolverOutput {
        guard let model = engine.vehicleModel(for: component) else { return .empty }
        let factors = model.factors
        var metrics: [MetricKey: Measured] = [
            .lifespan: FactorRanges.relative(factors.lifespanYears, 0.25, unit: .years, sources: [factors.lifespanCitation]),
            .recyclablePercent: FactorRanges.percent(factors.recyclablePercent, spread: 10, sources: [factors.endOfLifeCitation]),
        ]
        let massG = model.tonnes * 1_000_000
        if let blend = MaterialBlend(materials: component.identifiers.materials, massG: massG, store: store), blend.plasticG > 0 {
            metrics[.plasticMass] = blend.endOfLifeMetrics()[.plasticMass]
        } else {
            metrics[.plasticMass] = FactorRanges.relative(massG * factors.plasticMassShare, 0.3, unit: .grams,
                                                          sources: [factors.endOfLifeCitation])
        }
        if let kWh = model.yearlyElectricity(component.usage, seed: component.stableSeed) {
            metrics[.yearlyElectricity] = kWh
        }
        var working = component
        if working.metrics[.lifespan] == nil { working.metrics[.lifespan] = metrics[.lifespan] }
        let lifetime = engine.vehicleLifetimeCarbon(production: model.production, of: working, model: model, profile: profile)
        metrics[.carbon] = lifetime.carbon
        return ResolverOutput(metrics: metrics, stageShares: lifetime.stages, plasticPackagingShare: 0)
    }
}
