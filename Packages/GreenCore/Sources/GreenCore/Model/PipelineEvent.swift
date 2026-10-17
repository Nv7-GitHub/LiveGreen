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
    /// Live identify progress while the vision model is still answering.
    case identifyProgress(IdentifyProgress)
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

/// What the vision model has produced so far: item names as they stream in, and how much it has written.
public struct IdentifyProgress: Sendable, Hashable {
    public var itemNames: [String]
    public var sceneTitle: String?
    public var receivedCharacters: Int

    public init(itemNames: [String] = [], sceneTitle: String? = nil, receivedCharacters: Int = 0) {
        self.itemNames = itemNames
        self.sceneTitle = sceneTitle
        self.receivedCharacters = receivedCharacters
    }

    /// Reads the partial `report_components` JSON: every completed component `"name"` and the scene title.
    /// Only components carry a `name` key in that schema, so a plain scan is enough.
    public static func parsing(partialJSON text: String) -> IdentifyProgress {
        IdentifyProgress(itemNames: strings(for: "name", in: text), sceneTitle: strings(for: "scene_title", in: text).first,
                         receivedCharacters: text.count)
    }

    static func strings(for key: String, in text: String) -> [String] {
        let pattern = "\"\(key)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).replacingOccurrences(of: "\\\"", with: "\"") }
        }
    }
}
