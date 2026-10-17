/// A clarifying question the identify step says could narrow a metric (spec §5.3, §5.5).
public struct ComponentQuestion: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var question: String
    public var whyItMatters: String
    public var affectedMetrics: [MetricKey]
    public var options: [AnswerOption]

    public init(id: String, question: String, whyItMatters: String, affectedMetrics: [MetricKey], options: [AnswerOption]) {
        self.id = id
        self.question = question
        self.whyItMatters = whyItMatters
        self.affectedMetrics = affectedMetrics
        self.options = options
    }
}

/// A chip answer; choosing it sets `field` on the component's `UsageProfile` to `value`.
public struct AnswerOption: Codable, Sendable, Hashable {
    public var label: String
    public var field: UsageField?
    public var value: Double?

    public init(label: String, field: UsageField? = nil, value: Double? = nil) {
        self.label = label
        self.field = field
        self.value = value
    }
}

/// A question attached to a specific component, ready for the questions sheet.
public struct PendingQuestion: Codable, Sendable, Hashable, Identifiable {
    public var componentID: Component.ID
    public var componentName: String
    public var question: ComponentQuestion

    public var id: String { "\(componentID.uuidString)/\(question.id)" }

    public init(componentID: Component.ID, componentName: String, question: ComponentQuestion) {
        self.componentID = componentID
        self.componentName = componentName
        self.question = question
    }
}
