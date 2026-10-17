import Foundation
import GreenCore

/// Returns pre-recorded researched values keyed by lowercased model number; empty otherwise.
public struct FakeSpecResearcher: SpecResearcher {
    public var valuesByModel: [String: [ResearchedValue]]
    public var latency: Duration

    public init(valuesByModel: [String: [ResearchedValue]] = FakeSpecResearcher.defaultValues, latency: Duration = .zero) {
        self.valuesByModel = valuesByModel
        self.latency = latency
    }

    public func research(name: String, category: GreenCore.Category, identifiers: Identifiers,
                         metrics: [MetricKey]) async throws -> ResearchedSpec {
        try await simulateLatency(latency)
        let values = identifiers.model.flatMap { valuesByModel[$0.lowercased()] } ?? []
        return ResearchedSpec(values: values.filter { metrics.contains($0.metric) })
    }

    public static let defaultValues: [String: [ResearchedValue]] = [
        "s2721h": [
            ResearchedValue(metric: .powerOn, value: 18, citation: Citation(
                url: URL(string: "https://www.dell.com/support/home/en-us/product-support/product/dell-s2721h-monitor/docs")!,
                title: "Dell S2721H User's Guide", quotedText: "Power consumption (typical): 18 W")),
        ],
    ]
}
