/// Modeled default lifecycle splits by category, used when no record supplies one (spec §6 flow view).
public enum StageModel {
    public static func defaultCarbonShares(for category: Category) -> [LifecycleStage: Double] {
        switch category {
        case .food: [.materials: 0.75, .manufacturing: 0.08, .transport: 0.07, .endOfLife: 0.10]
        case .electronic: [.materials: 0.45, .manufacturing: 0.20, .transport: 0.04, .use: 0.30, .endOfLife: 0.01]
        case .clothing: [.materials: 0.25, .manufacturing: 0.50, .transport: 0.05, .use: 0.15, .endOfLife: 0.05]
        case .packaging: [.materials: 0.60, .manufacturing: 0.25, .transport: 0.10, .endOfLife: 0.05]
        case .household: [.materials: 0.50, .manufacturing: 0.25, .transport: 0.10, .use: 0.10, .endOfLife: 0.05]
        case .personalCare: [.materials: 0.45, .manufacturing: 0.25, .transport: 0.10, .use: 0.15, .endOfLife: 0.05]
        // A typical petrol car over 15 years: driving is about 90% of its life's carbon.
        case .vehicle: [.materials: 0.08, .manufacturing: 0.015, .transport: 0.003, .use: 0.9, .endOfLife: 0.002]
        }
    }

    /// Shares scaled to sum to 1, dropping non-positive entries.
    public static func normalized(_ shares: [LifecycleStage: Double]) -> [LifecycleStage: Double] {
        let positive = shares.filter { $0.value > 0 }
        let total = positive.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return positive.mapValues { $0 / total }
    }
}

extension ImpactEngine {
    /// Lifecycle split of one metric for the flow view. Empty for metrics that are not flows
    /// (lifespan, repairability, recyclability, decomposition, power ratings).
    public func stageShares(for component: Component, metric: MetricKey = .carbon) -> [LifecycleStage: Double] {
        switch metric {
        case .yearlyElectricity:
            return [.use: 1]
        case .carbon:
            let recorded = StageModel.normalized(component.stageShares)
            return recorded.isEmpty ? StageModel.defaultCarbonShares(for: component.category) : recorded
        case .water, .land, .waterPollution:
            // Freshwater, land and nutrient runoff are dominated by raw-material production.
            switch component.category {
            case .food, .clothing: return [.materials: 0.9, .manufacturing: 0.1]
            default: return [.materials: 0.6, .manufacturing: 0.4]
            }
        case .plasticMass:
            return [.materials: 1]
        case .powerOn, .standbyPower, .lifespan, .repairability, .recyclablePercent, .decompositionTime:
            return [:]
        }
    }

    /// The metric's value split across lifecycle stages, each with a proportionally scaled range.
    public func stageBreakdown(_ component: Component, metric: MetricKey = .carbon) -> [LifecycleStage: Measured] {
        guard let measured = component.metrics[metric] else { return [:] }
        return stageShares(for: component, metric: metric).mapValues { measured.scaled(by: $0) }
    }
}
