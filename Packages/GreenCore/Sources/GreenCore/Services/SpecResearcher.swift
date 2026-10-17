import Foundation

/// T2 resolver backend (spec §5.4): a Claude call with `web_search` + `web_fetch` server tools that
/// returns values only with the URL and quoted text they came from. Uncited values must be discarded.
public protocol SpecResearcher: Sendable {
    /// - Parameter metrics: The metrics still missing for this component.
    func research(name: String, category: Category, identifiers: Identifiers, metrics: [MetricKey]) async throws -> ResearchedSpec
}

/// Researched values with citations.
public struct ResearchedSpec: Codable, Sendable, Hashable {
    public var values: [ResearchedValue]

    public init(values: [ResearchedValue]) {
        self.values = values
    }

    /// Values that carry a citation, converted to T2 `Measured` (first value per metric wins).
    public var measured: [MetricKey: Measured] {
        var out: [MetricKey: Measured] = [:]
        for value in values where value.citation.isValid && out[value.metric] == nil {
            out[value.metric] = value.asMeasured
        }
        return out
    }
}

/// One cited value in the metric's canonical unit.
public struct ResearchedValue: Codable, Sendable, Hashable {
    public var metric: MetricKey
    public var value: Double
    public var low: Double?
    public var high: Double?
    public var citation: Citation

    public init(metric: MetricKey, value: Double, low: Double? = nil, high: Double? = nil, citation: Citation) {
        self.metric = metric
        self.value = value
        self.low = low
        self.high = high
        self.citation = citation
    }

    /// Spec-sheet values default to ±10% when no range is given.
    public var asMeasured: Measured {
        let source = Source(title: citation.title, url: citation.url, tier: .researchedSpec, quote: citation.quotedText)
        if let low, let high {
            return Measured(value: value, low: low, high: high, unit: metric.unit, tier: .researchedSpec, sources: [source])
        }
        return Measured(value: value, relativeRange: 0.1, unit: metric.unit, tier: .researchedSpec, sources: [source])
    }
}

/// Where a researched value came from.
public struct Citation: Codable, Sendable, Hashable {
    public var url: URL
    public var title: String
    public var quotedText: String

    public init(url: URL, title: String, quotedText: String) {
        self.url = url
        self.title = title
        self.quotedText = quotedText
    }

    public var isValid: Bool {
        !quotedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && url.scheme?.hasPrefix("http") == true
    }
}
