import Foundation

/// One identified part of a scanned scene (spec §4).
public struct Component: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var category: Category
    /// Normalized 0–1 box in the captured frame.
    public var boundingBox: NormalizedRect
    public var identifiers: Identifiers
    public var quantities: Quantities
    /// Only metrics applicable to `category`.
    public var metrics: [MetricKey: Measured]
    public var usage: UsageProfile?
    public var alternatives: [Alternative]
    /// Set for deferrable chargers/loads.
    public var plugCandidate: PlugCandidate?
    /// Share of the component's carbon per lifecycle stage (fractions summing to ~1), if known.
    public var stageShares: [LifecycleStage: Double]
    /// Questions the identify step proposed for this component.
    public var questions: [ComponentQuestion]
    /// T4 estimates from the identify call, used only as a last resort.
    public var fallbackEstimates: [MetricKey: EstimateRange]

    public init(id: UUID = UUID(), name: String, category: Category, boundingBox: NormalizedRect = .full,
                identifiers: Identifiers = Identifiers(), quantities: Quantities = Quantities(),
                metrics: [MetricKey: Measured] = [:], usage: UsageProfile? = nil,
                alternatives: [Alternative] = [], plugCandidate: PlugCandidate? = nil,
                stageShares: [LifecycleStage: Double] = [:], questions: [ComponentQuestion] = [],
                fallbackEstimates: [MetricKey: EstimateRange] = [:]) {
        self.id = id
        self.name = name
        self.category = category
        self.boundingBox = boundingBox
        self.identifiers = identifiers
        self.quantities = quantities
        self.metrics = metrics
        self.usage = usage
        self.alternatives = alternatives
        self.plugCandidate = plugCandidate
        self.stageShares = stageShares
        self.questions = questions
        self.fallbackEstimates = fallbackEstimates
    }

    /// Applicable metrics that have not been resolved yet.
    public var missingMetrics: [MetricKey] {
        category.applicableMetrics.filter { metrics[$0] == nil }
    }
}

extension Component {
    /// Monte Carlo seed for this component's derived values: its identifier key when it has one, so a
    /// rescan of the same GTIN or brand|model gives identical ranges, else its id.
    public var stableSeed: UInt64 {
        identifiers.cacheKey.map(StableHash.fnv1a) ?? StableHash.seed(id)
    }
}
