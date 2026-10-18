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
    /// Share (0–1) of `plasticMass` that is packaging rather than the item itself; nil when unknown.
    public var plasticPackagingShare: Double?
    /// A point on the item itself from identify, where its pin points (`pinAnchor`); nil uses the box centre.
    public var anchor: NormalizedPoint?
    /// Why the scan left the item out of the user's totals (someone else's, background, seen on screen); nil when
    /// it counts. See `isCounted`.
    public var exclusion: Exclusion?
    /// The user's own answer ("Not mine", "Which is yours?"), which overrides `exclusion`; nil until they give one.
    public var markedOwned: Bool?

    public init(id: UUID = UUID(), name: String, category: Category, boundingBox: NormalizedRect = .full,
                identifiers: Identifiers = Identifiers(), quantities: Quantities = Quantities(),
                metrics: [MetricKey: Measured] = [:], usage: UsageProfile? = nil,
                alternatives: [Alternative] = [], plugCandidate: PlugCandidate? = nil,
                stageShares: [LifecycleStage: Double] = [:], questions: [ComponentQuestion] = [],
                fallbackEstimates: [MetricKey: EstimateRange] = [:], plasticPackagingShare: Double? = nil,
                anchor: NormalizedPoint? = nil, exclusion: Exclusion? = nil, markedOwned: Bool? = nil) {
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
        self.plasticPackagingShare = plasticPackagingShare
        self.anchor = anchor
        self.exclusion = exclusion
        self.markedOwned = markedOwned
    }

    /// Applicable metrics that have not been resolved yet.
    public var missingMetrics: [MetricKey] {
        category.applicableMetrics.filter { metrics[$0] == nil }
    }
}

extension Component {
    /// Key for the resolution cache and Monte Carlo seeds (`Identifiers.resolutionKey(category:quantities:)`).
    public var resolutionKey: String? {
        identifiers.resolutionKey(category: category, quantities: quantities)
    }

    /// Monte Carlo seed for this component's derived values: its identifier key when it has one, so a rescan of
    /// the same GTIN, brand|model, sized model line or kind of generic item gives identical ranges, else its id.
    public var stableSeed: UInt64 {
        resolutionKey.map(StableHash.fnv1a) ?? StableHash.seed(id)
    }
}

extension Component {
    /// Plastic split into the item's own and its packaging's (spec §4), when the split is known.
    public var plasticSplit: (item: Measured, packaging: Measured)? {
        guard let plastic = metrics[.plasticMass], let share = plasticPackagingShare else { return nil }
        let packaging = min(max(share, 0), 1)
        return (plastic.scaled(by: 1 - packaging), plastic.scaled(by: packaging))
    }
}
