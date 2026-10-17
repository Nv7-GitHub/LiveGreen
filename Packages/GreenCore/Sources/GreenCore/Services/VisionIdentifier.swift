import Foundation

/// Identifies the components in a captured frame (spec §5.3: one Claude vision call with
/// a forced `report_components` tool, temperature 0). Reports identifiers and quantities, not impacts.
public protocol VisionIdentifier: Sendable {
    /// - Parameters:
    ///   - image: JPEG, long edge ≤ 1568 px.
    ///   - hints: On-device OCR/barcode pre-pass output.
    ///   - profile: User context for default usage assumptions.
    func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse
}

/// Output of `report_components`.
public struct IdentifyResponse: Codable, Sendable, Hashable {
    public var components: [IdentifiedComponent]
    /// Short scene title, e.g. "Desk setup".
    public var sceneTitle: String?

    public init(components: [IdentifiedComponent], sceneTitle: String? = nil) {
        self.components = components
        self.sceneTitle = sceneTitle
    }
}

/// One component as reported by the identify call.
public struct IdentifiedComponent: Codable, Sendable, Hashable {
    public var name: String
    public var category: Category
    public var boundingBox: NormalizedRect
    public var identifiers: Identifiers
    public var quantities: Quantities
    public var defaultUsage: UsageProfile?
    /// Deferrable-load classification when the item is a charger or schedulable appliance.
    public var deferrableLoad: DeferrableLoadType?
    /// T4 fallback estimates in canonical units.
    public var estimates: [MetricKey: EstimateRange]
    public var needsQuestion: [ComponentQuestion]

    public init(name: String, category: Category, boundingBox: NormalizedRect, identifiers: Identifiers = Identifiers(),
                quantities: Quantities = Quantities(), defaultUsage: UsageProfile? = nil,
                deferrableLoad: DeferrableLoadType? = nil, estimates: [MetricKey: EstimateRange] = [:],
                needsQuestion: [ComponentQuestion] = []) {
        self.name = name
        self.category = category
        self.boundingBox = boundingBox
        self.identifiers = identifiers
        self.quantities = quantities
        self.defaultUsage = defaultUsage
        self.deferrableLoad = deferrableLoad
        self.estimates = estimates
        self.needsQuestion = needsQuestion
    }

    /// Converts to an unresolved `Component` (no metrics yet).
    public func makeComponent(id: UUID = UUID()) -> Component {
        Component(id: id, name: name, category: category, boundingBox: boundingBox.clamped,
                  identifiers: identifiers, quantities: quantities, usage: defaultUsage,
                  questions: needsQuestion, fallbackEstimates: estimates)
    }
}
