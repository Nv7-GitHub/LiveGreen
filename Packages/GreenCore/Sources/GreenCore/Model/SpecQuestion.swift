import Foundation

/// A plain-language detail asked before the results when an item's carbon is still a T4 estimate (no record,
/// research or factor-table match). Each option sets concrete quantities or reference materials, so the T3 factor
/// model can resolve the item once the user answers. Generated locally (`SpecQuestionCatalog`), never by the AI.
public struct SpecQuestion: Sendable, Hashable, Identifiable {
    public enum Topic: String, Sendable, Hashable {
        case material
        case size
        case foodType
        case portion
        case deviceKind
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
