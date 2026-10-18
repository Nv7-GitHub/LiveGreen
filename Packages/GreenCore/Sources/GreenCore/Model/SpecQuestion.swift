import Foundation

/// A plain-language detail asked before the results when an item's carbon is still a T4 estimate (no record,
/// research or factor-table match), or when a T3 food's group is one the AI picks inconsistently (dairy or plant
/// milk, the main protein). Each option sets concrete quantities, reference materials or a food group, so the T3
/// factor model can resolve the item once the user answers. Generated locally (`SpecQuestionCatalog`), never by the AI.
public struct SpecQuestion: Sendable, Hashable, Identifiable {
    public enum Topic: String, Sendable, Hashable {
        case material
        case size
        case foodType
        case portion
        case deviceKind

        /// Topics that describe what the item is made of and how big it is, where the AI's own estimate (which saw
        /// the item) is a sanity check: an answer that moves the carbon more than `ScanPipeline.refinementBand` from
        /// it is not offered (a "wood" SUV). What a food is, how big a portion is and what kind of device it is are
        /// the user's to say; their options are whole kinds whose numbers are meant to differ.
        public var isCheckedAgainstEstimate: Bool {
            switch self {
            case .material, .size: true
            case .foodType, .portion, .deviceKind: false
            }
        }
    }

    public var componentID: Component.ID
    public var componentName: String
    public var topic: Topic
    public var question: String
    public var options: [SpecOption]

    public var id: String { "\(componentID.uuidString)/\(topic.rawValue)" }

    public init(componentID: Component.ID, componentName: String, topic: Topic, question: String, options: [SpecOption]) {
        self.componentID = componentID
        self.componentName = componentName
        self.topic = topic
        self.question = question
        self.options = options
    }
}

/// One chip of a `SpecQuestion`: the values it fills in. Nil fields leave the component's own value alone.
public struct SpecOption: Sendable, Hashable, Identifiable {
    public var label: String
    public var materials: [MaterialShare]?
    public var massKg: Double?
    public var servingKg: Double?
    public var packagingMassG: Double?
    public var volumeLiters: Double?
    public var foodGroup: String?
    public var deviceType: String?

    public var id: String { label }

    /// Whether picking it changes anything; an option that sets nothing is never offered.
    public var setsSomething: Bool {
        materials != nil || massKg != nil || servingKg != nil || packagingMassG != nil || volumeLiters != nil
            || foodGroup != nil || deviceType != nil
    }

    public init(label: String, materials: [MaterialShare]? = nil, massKg: Double? = nil, servingKg: Double? = nil,
                packagingMassG: Double? = nil, volumeLiters: Double? = nil, foodGroup: String? = nil,
                deviceType: String? = nil) {
        self.label = label
        self.materials = materials
        self.massKg = massKg
        self.servingKg = servingKg
        self.packagingMassG = packagingMassG
        self.volumeLiters = volumeLiters
        self.foodGroup = foodGroup
        self.deviceType = deviceType
    }

    /// The component with this answer's values filled in.
    public func applied(to component: Component) -> Component {
        var result = component
        if let materials { result.identifiers.materials = materials }
        if let massKg { result.quantities.massKg = massKg }
        if let servingKg { result.quantities.servingKg = servingKg }
        if let packagingMassG { result.quantities.packagingMassG = packagingMassG }
        if let volumeLiters { result.quantities.volumeLiters = volumeLiters }
        if let foodGroup { result.quantities.foodGroup = foodGroup }
        if let deviceType { result.quantities.deviceType = deviceType }
        return result
    }
}

/// A chip the user picked for one spec question.
public struct SpecAnswer: Sendable, Hashable {
    public var componentID: Component.ID
    public var option: SpecOption

    public init(componentID: Component.ID, option: SpecOption) {
        self.componentID = componentID
        self.option = option
    }
}

/// A quick-details answer kept on the item it refined (`Component.detailAnswer`): what was picked, and the item's
/// identity and numbers from before, so the detail sheet can take the answer back.
public struct DetailAnswer: Codable, Sendable, Hashable {
    /// The chip's label, e.g. "Plastic".
    public var label: String
    public var identifiers: Identifiers
    public var quantities: Quantities
    public var metrics: [MetricKey: Measured]
    public var stageShares: [LifecycleStage: Double]
    public var plugCandidate: PlugCandidate?
    public var plasticPackagingShare: Double?

    /// The answer `label` given for `component`, remembering the component as it was.
    public init(label: String, before component: Component) {
        self.label = label
        identifiers = component.identifiers
        quantities = component.quantities
        metrics = component.metrics
        stageShares = component.stageShares
        plugCandidate = component.plugCandidate
        plasticPackagingShare = component.plasticPackagingShare
    }

    /// `component` as it was before the answer; its usage and everything else since are kept.
    public func restoring(_ component: Component) -> Component {
        var result = component
        result.identifiers = identifiers
        result.quantities = quantities
        result.metrics = metrics
        result.stageShares = stageShares
        result.plugCandidate = plugCandidate
        result.plasticPackagingShare = plasticPackagingShare
        result.detailAnswer = nil
        return result
    }
}
