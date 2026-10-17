/// T1: bundled ASUS Product Carbon Footprint reports, matched by model number (spec §5.4).
public struct ASUSPCFResolver: MetricResolver {
    public let tier = Tier.exactRecord
    public let name = "ASUS Product Carbon Footprint"
    public let store: ReferenceStore

    public init(store: ReferenceStore = .bundled) {
        self.store = store
    }

    public func resolve(_ request: ResolutionRequest) async throws -> ResolverOutput {
        let ids = request.component.identifiers
        guard request.component.category == .electronic, let model = ids.model,
              ids.brand.map({ $0.localizedCaseInsensitiveContains("asus") }) ?? true,
              let detail = store.asusDetail(model: model) else { return .empty }
        let record = detail.record
        let sources = [record.citation]
        // The report's ± figure, else ±15% (typical PAIA-model spread).
        let spread = detail.uncertaintyKgCO2e ?? record.totalKgCO2e * 0.15
        var metrics: [MetricKey: Measured] = [
            .carbon: Measured(value: record.totalKgCO2e, low: record.totalKgCO2e - spread, high: record.totalKgCO2e + spread,
                              unit: .kgCO2e, tier: .exactRecord, sources: sources),
            .yearlyElectricity: Measured(value: detail.annualKWh, relativeRange: 0.1, unit: .kilowattHoursPerYear,
                                         tier: .exactRecord, sources: sources),
        ]
        if let years = record.lifespanYears {
            metrics[.lifespan] = Measured.exact(years, unit: .years, tier: .exactRecord, sources: sources)
        }
        return ResolverOutput(metrics: metrics.filter { request.metrics.contains($0.key) }, stageShares: record.stageShares)
    }
}
