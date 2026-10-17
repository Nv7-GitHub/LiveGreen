import Foundation

/// User-visible steps of the scan pipeline (spec §10, analyzing state).
public enum PipelineStep: String, Codable, Sendable, Hashable, CaseIterable {
    case readingLabels
    case identifying
    case lookingUpRecords
    case researchingSpecs
    case computing

    public var displayName: String {
        switch self {
        case .readingLabels: "Reading labels"
        case .identifying: "Identifying"
        case .lookingUpRecords: "Looking up records"
        case .researchingSpecs: "Researching specs"
        case .computing: "Computing"
        }
    }
}

/// Progress emitted by the scan coordinator as an `AsyncThrowingStream<PipelineEvent, Error>`.
public enum PipelineEvent: Sendable, Hashable {
    case stepStarted(PipelineStep)
    case stepFinished(PipelineStep)
    /// Components are known (boxes can be drawn) but metrics may still be resolving.
    case componentsIdentified([Component])
    /// One metric of one component resolved at a tier.
    case metricResolved(componentID: UUID, metric: MetricKey, tier: Tier)
    /// Questions that pass the §5.5 gate; the UI shows them in one sheet.
    case questionsNeeded([PendingQuestion])
    /// A non-fatal problem, e.g. a resolver failed and the ladder fell through.
    case warning(String)
    /// The final result. Always the last event of a successful stream.
    case completed(ScanResult)
}
