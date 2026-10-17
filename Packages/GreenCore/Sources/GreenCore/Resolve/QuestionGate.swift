/// Decides which proposed questions to show (spec §5.5): the question must be in `needsQuestion`,
/// one of its affected metrics must have a wide range (high/low > 1.6), and the component must be
/// one of the scan's top-two carbon contributors.
public enum QuestionGate {
    public static let spreadThreshold = 1.6

    public static func pendingQuestions(for components: [Component]) -> [PendingQuestion] {
        let topCarbon = components
            .compactMap { c in c.metrics[.carbon].map { (c.id, $0.value) } }
            .sorted { $0.1 > $1.1 }
            .prefix(2)
            .map(\.0)
        return components.filter { topCarbon.contains($0.id) }.flatMap { component in
            component.questions
                .filter { question in
                    question.affectedMetrics.contains { (component.metrics[$0]?.spreadRatio ?? 0) > spreadThreshold }
                }
                .map { PendingQuestion(componentID: component.id, componentName: component.name, question: $0) }
        }
    }

    /// Drops questions the user has answered or declined ("Use estimate"), so a saved scan doesn't ask again.
    public static func settling(_ settled: [PendingQuestion], in components: [Component]) -> [Component] {
        let ids = Set(settled.map(\.id))
        return components.map { component in
            var updated = component
            updated.questions.removeAll { question in
                ids.contains(PendingQuestion(componentID: component.id, componentName: component.name,
                                             question: question).id)
            }
            return updated
        }
    }
}
