/// A mass split across reference materials, for packaging and material-based items.
struct MaterialBlend {
    struct Part {
        var factor: MaterialFactor
        var grams: Double
    }

    let parts: [Part]

    /// Resolves material names; nil when under half of the stated share matches a reference material.
    init?(materials: [MaterialShare], massG: Double, store: ReferenceStore) {
        let resolved = materials.compactMap { share in
            store.materialFactor(material: share.material).map { (factor: $0, percent: max(share.percent, 0)) }
        }
        let statedTotal = materials.reduce(0) { $0 + max($1.percent, 0) }
        let resolvedTotal = resolved.reduce(0) { $0 + $1.percent }
        guard massG > 0, statedTotal > 0, resolvedTotal >= statedTotal / 2 else { return nil }
        parts = resolved.map { Part(factor: $0.factor, grams: massG * $0.percent / resolvedTotal) }
    }

    /// Blends side by side, such as a product's contents and its container; nil when none has mass.
    init?(combining blends: [MaterialBlend]) {
        let parts = blends.flatMap(\.parts)
        guard parts.contains(where: { $0.grams > 0 }) else { return nil }
        self.parts = parts
    }

    var massG: Double { parts.reduce(0) { $0 + $1.grams } }

    /// What is thrown away at the end: everything but what use consumes (a cleaner's formula).
    private var discarded: [Part] { parts.filter { !$0.factor.isConsumed } }

    var plasticG: Double {
        discarded.filter(\.factor.endOfLife.isPlastic).reduce(0) { $0 + $1.grams }
    }

    /// Mass-weighted recycling rate of what is thrown away; nil when everything is used up.
    var recyclablePercent: Double? {
        Self.weighted(discarded) { $0.endOfLife.recyclablePercent }
    }

    /// Mass-weighted decomposition time of what is thrown away, inert materials left out: glass or ceramic
    /// lingers without polluting. A weighted mean moves smoothly with the split, where the longest-lived material
    /// flipped between 500 and 1,000,000 years on a few percent of glass. Nil when nothing left breaks down.
    var decompositionYears: Double? {
        Self.weighted(discarded.filter { !$0.factor.isInert }) { $0.endOfLife.decompositionYears }
    }

    var kgCO2e: Double {
        parts.reduce(0) { $0 + $1.grams / 1000 * $1.factor.kgCO2ePerKg }
    }

    var liters: Double {
        parts.reduce(0) { $0 + $1.grams / 1000 * $1.factor.litersPerKg }
    }

    /// Share of the mass whose production footprint the table models; `electronics_mixed` is listed at 0 because
    /// material factors cannot price chips and boards.
    var modelledShare: Double {
        let total = massG
        return total > 0 ? parts.filter { $0.factor.kgCO2ePerKg > 0 }.reduce(0) { $0 + $1.grams } / total : 0
    }

    var sources: [Source] {
        var seen = Set<Source>()
        return parts.map(\.factor.citation).filter { seen.insert($0).inserted }
    }

    /// Plastic, recyclability and decomposition metrics shared by every material-based category. Recyclability
    /// and decomposition are left out when nothing is thrown away or nothing breaks down.
    func endOfLifeMetrics() -> [MetricKey: Measured] {
        var metrics: [MetricKey: Measured] = [
            .plasticMass: Measured(value: plasticG, relativeRange: 0.3, unit: .grams, tier: .factorModel, sources: sources),
        ]
        if let recyclablePercent {
            metrics[.recyclablePercent] = FactorRanges.percent(recyclablePercent, spread: 15, sources: sources)
        }
        if let decompositionYears {
            metrics[.decompositionTime] = FactorRanges.multiplicative(decompositionYears, factor: 2, unit: .years, sources: sources)
        }
        return metrics
    }

    private static func weighted(_ parts: [Part], _ value: (MaterialFactor) -> Double) -> Double? {
        let total = parts.reduce(0) { $0 + $1.grams }
        guard total > 0 else { return nil }
        return parts.reduce(0) { $0 + $1.grams * value($1.factor) } / total
    }
}

/// Range conventions for factor-model (T3) values.
enum FactorRanges {
    /// value ×/÷ factor, e.g. food factors vary ~1.6× between producers (Poore & Nemecek 2018).
    static func multiplicative(_ value: Double, factor: Double, unit: MetricUnit, sources: [Source]) -> Measured {
        Measured(value: value, low: value / factor, high: value * factor, unit: unit, tier: .factorModel, sources: sources)
    }

    /// Absolute ± spread clamped to 0–100.
    static func percent(_ value: Double, spread: Double, sources: [Source]) -> Measured {
        Measured(value: value, low: max(value - spread, 0), high: min(value + spread, 100), unit: .percent,
                 tier: .factorModel, sources: sources)
    }

    /// Absolute ± spread clamped to 0–10.
    static func score(_ value: Double, spread: Double, sources: [Source]) -> Measured {
        Measured(value: value, low: max(value - spread, 0), high: min(value + spread, 10), unit: .score10,
                 tier: .factorModel, sources: sources)
    }

    static func relative(_ value: Double, _ fraction: Double, unit: MetricUnit, sources: [Source]) -> Measured {
        Measured(value: value, low: max(value * (1 - fraction), 0), high: value * (1 + fraction), unit: unit,
                 tier: .factorModel, sources: sources)
    }
}
