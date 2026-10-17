import Foundation

extension FactorModelResolver {
    // MARK: Electronics (per item lifetime)

    func electronic(_ component: Component, profile: UserProfile) -> ResolverOutput {
        let q = component.quantities
        guard let device = store.deviceProfile(deviceType: q.deviceType ?? component.name) else {
            return ratedPowerOnly(component)
        }
        let d = device.defaults
        let sources = [d.citation]
        // Displays scale power, embodied carbon and plastic with screen area.
        var scale = 1.0
        if let size = q.screenSizeInches, let reference = device.referenceScreenInches, size > 0, reference > 0 {
            scale = min(max(pow(size / reference, 2), 0.25), 4)
        }

        var metrics: [MetricKey: Measured] = [
            .powerOn: FactorRanges.relative(d.onWatts * scale, 0.35, unit: .watts, sources: sources),
            .standbyPower: FactorRanges.relative(d.standbyWatts, 0.5, unit: .watts, sources: sources),
            .lifespan: FactorRanges.relative(d.lifespanYears, 0.3, unit: .years, sources: sources),
            .repairability: FactorRanges.score(d.repairability, spread: 1.5, sources: sources),
        ]
        if let plastic = d.plasticMassG {
            metrics[.plasticMass] = FactorRanges.relative(plastic * scale, 0.4, unit: .grams, sources: sources)
        }
        if let recyclable = d.recyclablePercent {
            metrics[.recyclablePercent] = FactorRanges.percent(recyclable, spread: 15, sources: sources)
        }

        // Prefer values already resolved at better tiers when deriving electricity and carbon.
        var working = component
        for (metric, value) in metrics where working.metrics[metric] == nil { working.metrics[metric] = value }
        if working.usage == nil { working.usage = UsageProfile(hoursOnPerDay: d.typicalHoursOnPerDay) }
        let kWh = working.metrics[.yearlyElectricity] ?? engine.derivedYearlyElectricity(for: working)
        if let kWh { metrics[.yearlyElectricity] = kWh }

        let embodied = FactorRanges.relative(d.embodiedKgCO2e * scale, 0.4, unit: .kgCO2e, sources: sources)
        let lifespan = engine.lifespan(of: working)
        let grid = engine.gridMeasured(for: profile)
        let yearlyKWh = kWh ?? Measured.exact(0, unit: .kilowattHoursPerYear, tier: .factorModel)
        let mc = MonteCarlo(seed: component.stableSeed)
        let carbon = mc.propagate([embodied, yearlyKWh, grid, lifespan], unit: .kgCO2e, salt: "factor.carbon") {
            ImpactEngine.lifetimeCarbon(embodiedKg: $0[0], lifespanYears: $0[3],
                                        annualUseKg: ImpactEngine.useCarbon(kWh: $0[1], gramsPerKWh: $0[2]))
        }
        metrics[.carbon] = Measured(value: carbon.value, low: carbon.low, high: carbon.high, unit: .kgCO2e,
                                    tier: .factorModel, sources: carbon.sources)

        // Embodied split from the table plus the use phase computed here.
        let useKg = ImpactEngine.useCarbon(kWh: yearlyKWh.value, gramsPerKWh: grid.value) * lifespan.value
        var stages = StageModel.normalized(d.stageShares).mapValues { $0 * embodied.value }
        stages[.use, default: 0] += useKg
        return ResolverOutput(metrics: metrics, stageShares: StageModel.normalized(stages))
    }

    /// Unknown device type: only a label wattage is known; typical draw is taken as half of it (±50%).
    private func ratedPowerOnly(_ component: Component) -> ResolverOutput {
        guard let rated = component.quantities.ratedPowerW, rated > 0 else { return .empty }
        let source = Source(title: "Label rating × 0.5 typical-load factor", tier: .factorModel)
        return ResolverOutput(metrics: [.powerOn: FactorRanges.relative(rated * 0.5, 0.5, unit: .watts, sources: [source])])
    }

    // MARK: Clothing (per garment lifetime)

    func clothing(_ component: Component) -> ResolverOutput {
        guard let massKg = component.quantities.massKg, massKg > 0, let garment = store.garment else { return .empty }
        let fibers = component.identifiers.materials.compactMap { share in
            store.fiberFactor(material: share.material).map { (fiber: $0, name: share.material, percent: max(share.percent, 0)) }
        }
        let total = fibers.reduce(0) { $0 + $1.percent }
        guard total > 0 else { return .empty }
        let parts = fibers.map { (fiber: $0.fiber, name: $0.name, fraction: $0.percent / total) }
        var seen = Set<Source>()
        let sources = (parts.map(\.fiber.citation) + [garment.citation]).filter { seen.insert($0).inserted }

        func weighted(_ value: (FiberFactor) -> Double) -> Double { parts.reduce(0) { $0 + $1.fraction * value($1.fiber) } }
        let fiberCarbon = massKg * weighted(\.kgCO2ePerKg)
        let processCarbon = massKg * garment.kgCO2ePerKg
        var metrics: [MetricKey: Measured] = [
            .carbon: FactorRanges.relative(fiberCarbon + processCarbon, 0.4, unit: .kgCO2e, sources: sources),
            .water: FactorRanges.multiplicative(massKg * (weighted(\.litersPerKg) + garment.litersPerKg), factor: 1.8,
                                                unit: .liters, sources: sources),
            .land: FactorRanges.multiplicative(massKg * weighted(\.landM2YearPerKg), factor: 1.8,
                                               unit: .squareMeterYears, sources: sources),
            .waterPollution: FactorRanges.multiplicative(massKg * (weighted(\.gPO4ePerKg) + garment.gPO4ePerKg), factor: 1.8,
                                                         unit: .gramsPO4e, sources: sources),
            .plasticMass: FactorRanges.relative(massKg * 1000 * parts.filter(\.fiber.isSynthetic).reduce(0) { $0 + $1.fraction },
                                                0.1, unit: .grams, sources: sources),
            .lifespan: FactorRanges.relative(garment.lifespanYears, 0.4, unit: .years, sources: [garment.lifespanCitation]),
        ]
        let endOfLife = parts.compactMap { part in store.endOfLife(material: part.name).map { (eol: $0, fraction: part.fraction) } }
        if !endOfLife.isEmpty {
            let eolSources = endOfLife.map(\.eol.citation)
            let recyclable = endOfLife.reduce(0) { $0 + $1.fraction * $1.eol.recyclablePercent }
            let decomposition = endOfLife.filter { $0.fraction >= 0.05 }.map(\.eol.decompositionYears).max() ?? 0
            metrics[.recyclablePercent] = FactorRanges.percent(recyclable, spread: 10, sources: eolSources)
            metrics[.decompositionTime] = FactorRanges.multiplicative(decomposition, factor: 2, unit: .years, sources: eolSources)
        }
        var stages = StageModel.defaultCarbonShares(for: .clothing)
        let carbonTotal = fiberCarbon + processCarbon
        if carbonTotal > 0 {
            let modeled = 1 - (stages[.transport] ?? 0) - (stages[.use] ?? 0) - (stages[.endOfLife] ?? 0)
            stages[.materials] = modeled * fiberCarbon / carbonTotal
            stages[.manufacturing] = modeled * processCarbon / carbonTotal
        }
        return ResolverOutput(metrics: metrics, stageShares: StageModel.normalized(stages))
    }

    // MARK: Household goods (per item lifetime)

    func household(_ component: Component) -> ResolverOutput {
        let q = component.quantities
        var metrics: [MetricKey: Measured] = [:]
        if let device = store.deviceProfile(deviceType: q.deviceType ?? component.name) {
            metrics[.lifespan] = FactorRanges.relative(device.defaults.lifespanYears, 0.3, unit: .years,
                                                       sources: [device.defaults.citation])
        }
        let massG = (q.massKg ?? 0) * 1000
        if let blend = MaterialBlend(materials: component.identifiers.materials, massG: massG, store: store) {
            metrics.merge(blend.endOfLifeMetrics()) { current, _ in current }
            metrics[.carbon] = FactorRanges.relative(blend.kgCO2e, 0.4, unit: .kgCO2e, sources: blend.sources)
            metrics[.water] = FactorRanges.relative(blend.liters, 0.5, unit: .liters, sources: blend.sources)
        }
        guard !metrics.isEmpty else { return .empty }
        return ResolverOutput(metrics: metrics, stageShares: metrics[.carbon] == nil ? [:] : StageModel.defaultCarbonShares(for: .household))
    }
}
