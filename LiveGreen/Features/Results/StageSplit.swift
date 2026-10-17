import GreenCore

/// Lifecycle-stage split for the flow view (spec §6). Carbon uses the component's recorded split
/// (OFF / ASUS PCF stage shares) when present; otherwise a typical split for the category.
nonisolated struct StageSplit: Equatable, Sendable {
    /// Fractions summing to 1, only stages with a positive share.
    let shares: [(stage: LifecycleStage, share: Double)]
    /// True when the split came from the component's own record.
    let isRecorded: Bool

    static func == (lhs: StageSplit, rhs: StageSplit) -> Bool {
        lhs.isRecorded == rhs.isRecorded && lhs.shares.map(\.stage) == rhs.shares.map(\.stage)
            && lhs.shares.map(\.share) == rhs.shares.map(\.share)
    }

    /// Metrics that can be meaningfully split across lifecycle stages.
    static let flowMetrics: [MetricKey] = [.carbon, .yearlyElectricity, .water, .land, .waterPollution]

    static func split(for component: Component, metric: MetricKey) -> StageSplit {
        if metric == .yearlyElectricity {
            return StageSplit(normalizing: [.use: 1], isRecorded: true)
        }
        if metric == .carbon, !component.stageShares.isEmpty {
            return StageSplit(normalizing: component.stageShares, isRecorded: true)
        }
        return StageSplit(normalizing: typical(component.category, metric: metric), isRecorded: false)
    }

    init(normalizing raw: [LifecycleStage: Double], isRecorded: Bool) {
        let sum = raw.values.filter { $0 > 0 }.reduce(0, +)
        shares = LifecycleStage.allCases.compactMap { stage in
            guard sum > 0, let value = raw[stage], value > 0 else { return nil }
            return (stage, value / sum)
        }
        self.isRecorded = isRecorded
    }

    /// Typical splits by category. Carbon shapes follow common LCA results: farm stage dominates food
    /// (Poore & Nemecek 2018), production dominates electronics and apparel. Water, land and
    /// eutrophication are mostly incurred where raw materials are grown or extracted.
    private static func typical(_ category: GreenCore.Category, metric: MetricKey) -> [LifecycleStage: Double] {
        switch metric {
        case .carbon:
            switch category {
            case .food: [.materials: 0.80, .manufacturing: 0.04, .transport: 0.06, .use: 0.05, .endOfLife: 0.05]
            case .electronic: [.materials: 0.35, .manufacturing: 0.40, .transport: 0.05, .use: 0.18, .endOfLife: 0.02]
            case .clothing: [.materials: 0.25, .manufacturing: 0.50, .transport: 0.05, .use: 0.15, .endOfLife: 0.05]
            case .packaging: [.materials: 0.60, .manufacturing: 0.20, .transport: 0.08, .endOfLife: 0.12]
            case .household: [.materials: 0.40, .manufacturing: 0.30, .transport: 0.08, .use: 0.15, .endOfLife: 0.07]
            case .personalCare: [.materials: 0.35, .manufacturing: 0.15, .transport: 0.05, .use: 0.40, .endOfLife: 0.05]
            }
        default:
            switch category {
            case .food, .clothing: [.materials: 0.90, .manufacturing: 0.07, .use: 0.03]
            case .personalCare: [.materials: 0.45, .manufacturing: 0.10, .use: 0.45]
            case .electronic, .packaging, .household: [.materials: 0.60, .manufacturing: 0.35, .use: 0.05]
            }
        }
    }
}

extension LifecycleStage {
    /// Short label for the flow view.
    nonisolated var flowLabel: String {
        switch self {
        case .materials: "Materials"
        case .manufacturing: "Making"
        case .transport: "Transport"
        case .use: "Use"
        case .endOfLife: "End of life"
        }
    }
}
