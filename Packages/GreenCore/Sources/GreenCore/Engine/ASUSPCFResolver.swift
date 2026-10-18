/// T1: bundled ASUS Product Carbon Footprint reports, matched by model number (spec §5.4). A laptop recognized by
/// its design, with a model line but no legible model number, gets the reports of that line instead, as a range
/// over them at the researched-spec tier (T2): the line is known, the exact model is not. Like a researched PCF,
/// that carbon leaves out the use phase, which the pipeline adds from the local grid (`addingUsePhase`).
public struct ASUSPCFResolver: MetricResolver {
    public let tier = Tier.exactRecord
    public let name = "ASUS Product Carbon Footprint"
    public let store: ReferenceStore

    public init(store: ReferenceStore = .bundled) {
        self.store = store
    }

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let ids = request.component.identifiers
        guard request.component.category == .electronic,
              ids.brand.map({ $0.localizedCaseInsensitiveContains("asus") }) ?? true else { return .empty }
        if let model = ids.model, let detail = store.asusDetail(model: model) {
            return Self.output([detail], tier: .exactRecord, metrics: request.metrics)
        }
        guard let line = ids.confidentModelLine else { return .empty }
        let details = store.asusDetails(modelLine: line)
        return details.isEmpty ? .empty : Self.output(details, tier: .researchedSpec, metrics: request.metrics)
    }

    /// One report's figures, or the span of several reports of one line (mean value, bounds covering each
    /// report's range).
    static func output(_ details: [ASUSPCFDetail], tier: Tier, metrics requested: Set<MetricKey>) -> ResolverOutput {
        let sources = details.map { detail in
            let citation = detail.record.citation
            return tier == .exactRecord ? citation
                : Source(title: "\(citation.title) (same model line)", url: citation.url, tier: tier)
        }
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
        // The report's ± figure, else ±15% (typical PAIA-model spread). A record's total includes the use phase;
        // T2 carbon is embodied only.
        let carbon = details.map { detail in
            let total = detail.record.totalKgCO2e
            let share = tier == .exactRecord ? 1 : 1 - (detail.record.stageShares[.use] ?? 0)
            return (value: total * share, spread: (detail.uncertaintyKgCO2e ?? total * 0.15) * share)
        }
        let kWh = details.map(\.annualKWh)
        let lowKWh = kWh.min() ?? 0, highKWh = kWh.max() ?? 0
        var metrics: [MetricKey: Measured] = [
            .carbon: Measured(value: mean(carbon.map(\.value)), low: carbon.map { $0.value - $0.spread }.min() ?? 0,
                              high: carbon.map { $0.value + $0.spread }.max() ?? 0, unit: .kgCO2e, tier: tier, sources: sources),
            .yearlyElectricity: Measured(value: mean(kWh), low: lowKWh - abs(lowKWh) * 0.1, high: highKWh + abs(highKWh) * 0.1,
                                         unit: .kilowattHoursPerYear, tier: tier, sources: sources),
        ]
        let years = details.compactMap(\.record.lifespanYears)
        if years.count == details.count, let low = years.min(), let high = years.max() {
            metrics[.lifespan] = Measured(value: mean(years), low: low, high: high, unit: .years, tier: tier, sources: sources)
        }
        var stageShares: [LifecycleStage: Double] = [:]
        for detail in details {
            for (stage, share) in detail.record.stageShares {
                stageShares[stage, default: 0] += share / Double(details.count)
            }
        }
        return ResolverOutput(metrics: metrics.filter { requested.contains($0.key) }, stageShares: stageShares)
    }
}
