import Foundation
import GreenCore

/// Accumulated pipeline state for the analyzing card.
struct PipelineProgress: Equatable {
    var started: Set<PipelineStep> = []
    var finished: Set<PipelineStep> = []
    var componentCount = 0
    var resolvedMetrics = 0

    mutating func apply(_ event: PipelineEvent) {
        switch event {
        case let .stepStarted(step): started.insert(step)
        case let .stepFinished(step): finished.insert(step)
        case let .componentsIdentified(components): componentCount = components.count
        case .metricResolved: resolvedMetrics += 1
        case .identifyProgress, .questionsNeeded, .warning, .completed: break
        }
    }
}
