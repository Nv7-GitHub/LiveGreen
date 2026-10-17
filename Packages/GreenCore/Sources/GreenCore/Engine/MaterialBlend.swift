/// A mass split across reference materials, for packaging and material-based items.
struct MaterialBlend {
    struct Part {
        var factor: MaterialFactor
        /// Fraction of the resolved mass, 0–1.
        var fraction: Double
    }

    let parts: [Part]
    let massG: Double

    /// Resolves material names; nil when under half of the stated share matches a reference material.
    init?(materials: [MaterialShare], massG: Double, store: ReferenceStore) {
        let resolved = materials.compactMap { share in
            store.materialFactor(material: share.material).map { (factor: $0, percent: max(share.percent, 0)) }
        }
        let statedTotal = materials.reduce(0) { $0 + max($1.percent, 0) }
        let resolvedTotal = resolved.reduce(0) { $0 + $1.percent }
        guard massG > 0, statedTotal > 0, resolvedTotal >= statedTotal / 2 else { return nil }
        parts = resolved.map { Part(factor: $0.factor, fraction: $0.percent / resolvedTotal) }
        self.massG = massG
    }

    var plasticG: Double {
        parts.filter(\.factor.endOfLife.isPlastic).reduce(0) { $0 + $1.fraction * massG }
    }

    var recyclablePercent: Double {
        parts.reduce(0) { $0 + $1.fraction * $1.factor.endOfLife.recyclablePercent }
    }

    /// The longest-lived material that is at least 5% of the mass: what lingers decides decomposition.
    var decompositionYears: Double {
        parts.filter { $0.fraction >= 0.05 }.map(\.factor.endOfLife.decompositionYears).max() ?? 0
    }

    var kgCO2e: Double {
        parts.reduce(0) { $0 + $1.fraction * massG / 1000 * $1.factor.kgCO2ePerKg }
    }

    var liters: Double {
        parts.reduce(0) { $0 + $1.fraction * massG / 1000 * $1.factor.litersPerKg }
    }

    var sources: [Source] {
        var seen = Set<Source>()
        return parts.map(\.factor.citation).filter { seen.insert($0).inserted }
    }

    /// Plastic, recyclability and decomposition metrics shared by every material-based category.
    func endOfLifeMetrics() -> [MetricKey: Measured] {
        [
            .plasticMass: Measured(value: plasticG, relativeRange: 0.3, unit: .grams, tier: .factorModel, sources: sources),
            .recyclablePercent: FactorRanges.percent(recyclablePercent, spread: 15, sources: sources),
            .decompositionTime: FactorRanges.multiplicative(decompositionYears, factor: 2, unit: .years, sources: sources),
        ]
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
