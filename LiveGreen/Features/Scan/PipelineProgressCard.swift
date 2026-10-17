import SwiftUI
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
        case .questionsNeeded, .warning, .completed: break
        }
    }
}

/// Glass card listing live pipeline steps (spec §10, analyzing state).
struct PipelineProgressCard: View {
    let progress: PipelineProgress

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PipelineStep.allCases, id: \.self) { step in
                    HStack {
                        icon(for: step).frame(width: 22)
                        Text(step.displayName)
                        Spacer()
                        if step == .identifying, progress.componentCount > 0 {
                            Text("\(progress.componentCount) items").foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .accessibilityIdentifier("pipelineProgress")
    }

    @ViewBuilder private func icon(for step: PipelineStep) -> some View {
        if progress.finished.contains(step) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.leaf)
        } else if progress.started.contains(step) {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}
