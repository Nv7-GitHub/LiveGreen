import Foundation

/// Identifies the components in a captured frame (spec §5.3: one Claude vision call with
/// a forced `report_components` tool, temperature 0). Reports identifiers and quantities, not impacts.
public protocol VisionIdentifier: Sendable {
    /// - Parameters:
    ///   - image: JPEG within `IdentifyImage` limits (long edge ≤ 2576 px, ~3.7 MP).
    ///   - hints: On-device OCR/barcode pre-pass output.
    ///   - profile: User context for default usage assumptions.
    func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse

    /// Same call, reporting partial results while the model answers. Identifiers that cannot stream
    /// use the default, which reports nothing.
    func identify(image: Data, hints: OCRHints, profile: UserProfile,
                  progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse

    /// Same streaming call with notes the user left on earlier scans, which the model may take as weak hints
    /// (`ScanFeedback.promptSection`). Identifiers that cannot use them keep the default, which ignores them.
    func identify(image: Data, hints: OCRHints, profile: UserProfile, feedback: [ScanFeedback],
                  progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse
}

extension VisionIdentifier {
    public func identify(image: Data, hints: OCRHints, profile: UserProfile,
                         progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse {
        try await identify(image: image, hints: hints, profile: profile)
    }

    public func identify(image: Data, hints: OCRHints, profile: UserProfile, feedback: [ScanFeedback],
                         progress: @escaping @Sendable (IdentifyProgress) -> Void) async throws -> IdentifyResponse {
        try await identify(image: image, hints: hints, profile: profile, progress: progress)
    }
}

/// Output of `report_components`.
public struct IdentifyResponse: Codable, Sendable, Hashable {
    public var components: [IdentifiedComponent]
    /// Short scene title, e.g. "Desk setup".
    public var sceneTitle: String?
    /// Whose things these are likely to be: the user's own, a store display, a street or a screenshot.
    public var sceneContext: SceneContext?
    /// Screenshots: the photo or product image inside the app's interface, which the scan's photo is cropped to.
    public var photoRegion: NormalizedRect?

    public init(components: [IdentifiedComponent], sceneTitle: String? = nil, sceneContext: SceneContext? = nil,
                photoRegion: NormalizedRect? = nil) {
        self.components = components
        self.sceneTitle = sceneTitle
        self.sceneContext = sceneContext
        self.photoRegion = photoRegion
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
    /// A point on the item itself, where its pin goes when it lies in or near the box.
    public var anchor: NormalizedPoint?
    /// The plain generic noun for what the item is ("backpack"), which its generic key prefers over the name.
    public var kind: String?
    /// False when identify judged the item not the user's (someone else's, store stock, a fixture); nil when it
    /// did not say.
    public var likelyOwned: Bool?
    /// True for an incidental item only partly visible behind what the photo is of.
    public var background: Bool?

    public init(name: String, category: Category, boundingBox: NormalizedRect, identifiers: Identifiers = Identifiers(),
                quantities: Quantities = Quantities(), defaultUsage: UsageProfile? = nil,
                deferrableLoad: DeferrableLoadType? = nil, estimates: [MetricKey: EstimateRange] = [:],
                needsQuestion: [ComponentQuestion] = [], anchor: NormalizedPoint? = nil, kind: String? = nil,
                likelyOwned: Bool? = nil, background: Bool? = nil) {
        self.name = name
        self.category = category
        self.boundingBox = boundingBox
        self.identifiers = identifiers
        self.quantities = quantities
        self.defaultUsage = defaultUsage
        self.deferrableLoad = deferrableLoad
        self.estimates = estimates
        self.needsQuestion = needsQuestion
        self.anchor = anchor
        self.kind = kind
        self.likelyOwned = likelyOwned
        self.background = background
    }

    /// Converts to an unresolved `Component` (no metrics yet), left out of the user's totals when `scene` and
    /// identify's ownership call say so (`exclusion(in:)`).
    public func makeComponent(id: UUID = UUID(), scene: SceneContext? = nil) -> Component {
        Component(id: id, name: name, category: category, boundingBox: boundingBox.clamped,
                  identifiers: identifiers, quantities: quantities, usage: defaultUsage,
                  questions: needsQuestion, fallbackEstimates: estimates, anchor: anchor?.clamped,
                  exclusion: exclusion(in: scene))
    }
}
