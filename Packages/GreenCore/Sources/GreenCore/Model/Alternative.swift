import Foundation

/// A greener swap for a component (spec §7). Resolved through the same ladder as originals.
public struct Alternative: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        /// A different product.
        case product
        /// "Shelly smart plug + green-hours scheduling", added locally for deferrable loads.
        case smartPlugScheduling
    }

    public let id: UUID
    public var kind: Kind
    public var name: String
    public var category: Category
    public var identifiers: Identifiers
    public var quantities: Quantities
    public var usage: UsageProfile?
    public var rationale: String
    public var practicality: Practicality
    public var metrics: [MetricKey: Measured]
    public var fallbackEstimates: [MetricKey: EstimateRange]

    public init(id: UUID = UUID(), kind: Kind = .product, name: String, category: Category,
                identifiers: Identifiers = Identifiers(), quantities: Quantities = Quantities(),
                usage: UsageProfile? = nil, rationale: String, practicality: Practicality = Practicality(),
                metrics: [MetricKey: Measured] = [:], fallbackEstimates: [MetricKey: EstimateRange] = [:]) {
        self.id = id
        self.kind = kind
        self.name = name
        self.category = category
        self.identifiers = identifiers
        self.quantities = quantities
        self.usage = usage
        self.rationale = rationale
        self.practicality = practicality
        self.metrics = metrics
        self.fallbackEstimates = fallbackEstimates
    }
}

/// Cost and effort of adopting an alternative.
public struct Practicality: Codable, Sendable, Hashable {
    public enum CostTier: String, Codable, Sendable, Hashable, CaseIterable { case lower, similar, higher }
    public enum Effort: String, Codable, Sendable, Hashable, CaseIterable { case easy, moderate, hard }

    public var cost: CostTier
    public var effort: Effort

    public init(cost: CostTier = .similar, effort: Effort = .easy) {
        self.cost = cost
        self.effort = effort
    }
}
