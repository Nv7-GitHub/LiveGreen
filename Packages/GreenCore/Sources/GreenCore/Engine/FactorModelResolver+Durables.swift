import Foundation

extension FactorModelResolver {
    // MARK: Electronics (per item lifetime)

    func electronic(_ component: Component, profile: UserProfile) -> ResolverOutput {
        let q = component.quantities
        guard let device = store.deviceProfile(deviceType: q.deviceType ?? component.name) else {
            return unknownDevice(component)
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
        return ResolverOutput(metrics: metrics, stageShares: StageModel.normalized(stages),
                              plasticPackagingShare: metrics[.plasticMass] == nil ? nil : 0)
    }

    /// Unknown device type: typical draw is half the label wattage (±50%), plastic comes from the reported mass and
    /// materials, and recyclability is the documented global e-waste recycling rate. Carbon is left to better
    /// evidence or the estimate: material factors alone miss the electronics.
    func unknownDevice(_ component: Component) -> ResolverOutput {
        var metrics: [MetricKey: Measured] = [:]
        if let rated = component.quantities.ratedPowerW, rated > 0 {
            let source = Source(title: "Label rating × 0.5 typical-load factor", tier: .factorModel)
            metrics[.powerOn] = FactorRanges.relative(rated * 0.5, 0.5, unit: .watts, sources: [source])
        }
        let massG = (component.quantities.massKg ?? 0) * 1000
        // Every device has some plastic, so a blend without any (all "electronics_mixed") is not read as zero.
        if let blend = MaterialBlend(materials: component.identifiers.materials, massG: massG, store: store), blend.plasticG > 0 {
            metrics[.plasticMass] = blend.endOfLifeMetrics()[.plasticMass]
        }
        if let eWaste = store.materialFactor(material: "electronics_mixed") {
            metrics[.recyclablePercent] = FactorRanges.percent(eWaste.endOfLife.recyclablePercent, spread: 10,
                                                               sources: [eWaste.citation])
        }
        return ResolverOutput(metrics: metrics, plasticPackagingShare: metrics[.plasticMass] == nil ? nil : 0)
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
        // Synthetic fibers without their own end-of-life row (elastane) behave like other synthetic textiles.
        let endOfLife = parts.compactMap { part in
            (store.endOfLife(material: part.name) ?? (part.fiber.isSynthetic ? store.endOfLife(material: "synthetic_textile") : nil))
                .map { (eol: $0, fraction: part.fraction) }
        }
        let covered = endOfLife.reduce(0) { $0 + $1.fraction }
        if covered > 0 {
            var seenEOL = Set<Source>()
            let eolSources = endOfLife.map(\.eol.citation).filter { seenEOL.insert($0).inserted }
            // Averaged over the fibers with end-of-life data, so a part without it does not read as unrecyclable.
            let recyclable = endOfLife.reduce(0) { $0 + $1.fraction * $1.eol.recyclablePercent } / covered
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
        // Synthetic fibers are the garment's own plastic.
        return ResolverOutput(metrics: metrics, stageShares: StageModel.normalized(stages), plasticPackagingShare: 0)
    }

    // MARK: Household goods (per item lifetime)

    /// Items this heavy (vehicles, machinery) are scrapped, not left to break down, so they get no decomposition time.
    static let scrappedMassG = 300_000.0

    /// Carbon and water need production data for nearly all of the mass; the rest is scaled like the known part.
    static let minModelledShare = 0.9

    /// Materials' share of a made good's cradle-to-gate carbon (the household stage split). Material factors stop at
    /// the factory gate, so what is made from them also takes forming, assembly, transport and disposal: a bike's
    /// materials (≈60–80 kg CO2e) are about half of its ≈120 kg.
    static var materialsShare: Double { StageModel.defaultCarbonShares(for: .household)[.materials] ?? 1 }

    static let processingSource = Source(
        title: "Forming, assembly, transport and disposal: materials taken as 55% of a made good's carbon (modeled)",
        tier: .factorModel)

    /// A filled product (a cleaner, a detergent) is its contents plus the container `packagingMassG` weighs, as for
    /// personal care: identify reports the contents in `materials` (`detergent_formula`) and the container in
    /// `packagingMaterials`, and only the container counts at end of life. Older answers described just the
    /// container in `materials` for a liquid product; its contents are then unknown, so carbon is left to better
    /// evidence instead of pricing the whole bottle as plastic. Anything else is one blend over its whole mass.
    /// Carbon is the materials plus the processing of what is made from them (`materialsShare`); a formula that is
    /// used up is already a finished product. A device lifespan applies only for an explicit device type
    /// (`Component.deviceLookupKey`), else the household lifespan table's (a bicycle, a table).
    func household(_ component: Component) -> ResolverOutput {
        let q = component.quantities
        var metrics: [MetricKey: Measured] = [:]
        if let device = store.deviceProfile(for: component) {
            metrics[.lifespan] = FactorRanges.relative(device.defaults.lifespanYears, 0.3, unit: .years,
                                                       sources: [device.defaults.citation])
        } else if let durable = engine.householdLifespan(of: component) {
            metrics[.lifespan] = FactorRanges.relative(durable.lifespanYears, 0.4, unit: .years, sources: [durable.citation])
        }
        let massG = (q.massKg ?? 0) * 1000
        let materials = outsideFood(component.identifiers.materials)
        let packagingG = massG > 0 ? min(max(q.packagingMassG ?? 0, 0), massG) : max(q.packagingMassG ?? 0, 0)
        let packaging = discarded(component.identifiers.packagingMaterials ?? [])
        let usesUp = materials.contains { store.materialFactor(material: $0.material)?.isConsumed == true }
        var container: MaterialBlend?
        var contents: MaterialBlend?
        var contentsKnown = true
        if packagingG > 0, !packaging.isEmpty {
            container = MaterialBlend(materials: packaging, massG: packagingG, store: store)
            contents = MaterialBlend(materials: materials, massG: massG - packagingG, store: store)
            contentsKnown = contents != nil || massG <= packagingG
        } else if packagingG > 0, (q.volumeLiters ?? 0) > 0, !usesUp {
            container = MaterialBlend(materials: materials, massG: packagingG, store: store)
            contentsKnown = false
        } else {
            contents = MaterialBlend(materials: materials, massG: massG, store: store)
        }
        var packagingShare = 0.0
        var stages: [LifecycleStage: Double] = [:]
        if let blend = MaterialBlend(combining: [container, contents].compactMap { $0 }) {
            var endOfLife = blend.endOfLifeMetrics()
            if massG >= Self.scrappedMassG { endOfLife[.decompositionTime] = nil }
            metrics.merge(endOfLife) { current, _ in current }
            if blend.plasticG > 0 { packagingShare = (container?.plasticG ?? 0) / blend.plasticG }
            if contentsKnown, blend.modelledShare >= Self.minModelledShare {
                let scale = 1 / blend.modelledShare
                let materialsKg = blend.kgCO2e * scale
                let madeKg = blend.parts.filter { !$0.factor.isConsumed }
                    .reduce(0) { $0 + $1.grams / 1000 * $1.factor.kgCO2ePerKg } * scale
                let processingKg = madeKg * (1 / Self.materialsShare - 1)
                metrics[.carbon] = FactorRanges.relative(materialsKg + processingKg, 0.4, unit: .kgCO2e,
                                                         sources: blend.sources + (processingKg > 0 ? [Self.processingSource] : []))
                metrics[.water] = FactorRanges.relative(blend.liters * scale, 0.5, unit: .liters, sources: blend.sources)
                stages = Self.householdStages(materialsKg: materialsKg, processingKg: processingKg)
            }
        }
        guard !metrics.isEmpty else { return .empty }
        return ResolverOutput(metrics: metrics, stageShares: stages,
                              plasticPackagingShare: metrics[.plasticMass] == nil ? nil : packagingShare)
    }

    /// The modeled split: materials as computed, processing over the household split's other stages. No use stage:
    /// nothing here draws power.
    static func householdStages(materialsKg: Double, processingKg: Double) -> [LifecycleStage: Double] {
        let defaults = StageModel.defaultCarbonShares(for: .household)
        let rest = defaults.filter { $0.key != .materials && $0.key != .use }
        let restTotal = rest.values.reduce(0, +)
        var stages: [LifecycleStage: Double] = [.materials: materialsKg]
        if restTotal > 0 {
            for (stage, share) in rest { stages[stage] = processingKg * share / restTotal }
        }
        return StageModel.normalized(stages)
    }
}
