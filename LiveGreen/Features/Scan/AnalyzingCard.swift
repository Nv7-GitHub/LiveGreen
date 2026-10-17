import SwiftUI
import GreenCore
import GreenCoreFakes

/// Glass progress card for the analyzing state (spec §10). It consumes the coordinator's event stream
/// itself, so the steps, identified items and per-tier counts reflect real pipeline progress.
struct AnalyzingCard: View {
    let events: AsyncThrowingStream<PipelineEvent, Error>
    var onQuestions: ([PendingQuestion]) -> Void = { _ in }
    let onComplete: (ScanResult) -> Void
    let onFailure: (Error) -> Void

    @State private var progress = PipelineProgress()
    @State private var components: [Component] = []
    @State private var tierCounts: [Tier: Int] = [:]
    @State private var lastWarning: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Analyzing").font(.headline)
                    Spacer()
                    Text("\(progress.finished.count)/\(PipelineStep.allCases.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(PipelineStep.allCases, id: \.self) { step in
                    stepRow(step)
                }
                if !components.isEmpty { componentChips }
                if let lastWarning {
                    Label(lastWarning, systemImage: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityIdentifier("analyzingCard")
        .task { await consume() }
    }

    private func stepRow(_ step: PipelineStep) -> some View {
        HStack(spacing: 10) {
            stepIcon(step).frame(width: 22)
            Text(step.displayName)
                .foregroundStyle(progress.started.contains(step) ? .primary : .secondary)
            Spacer()
            if let detail = detail(for: step) {
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder private func stepIcon(_ step: PipelineStep) -> some View {
        if progress.finished.contains(step) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.leaf)
                .transition(.scale.combined(with: .opacity))
        } else if progress.started.contains(step) {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    /// Live counts next to each step: items found, then metrics resolved at that step's tiers.
    private func detail(for step: PipelineStep) -> String? {
        let count: Int
        switch step {
        case .readingLabels: return nil
        case .identifying:
            return components.isEmpty ? nil : "\(components.count) items"
        case .lookingUpRecords: count = tierCounts[.exactRecord, default: 0]
        case .researchingSpecs: count = tierCounts[.researchedSpec, default: 0]
        case .computing: count = tierCounts[.factorModel, default: 0] + tierCounts[.estimate, default: 0]
        }
        return count > 0 ? "\(count) values" : nil
    }

    private var componentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(components) { component in
                    Label(component.name, systemImage: component.category.systemImage)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular.tint(Theme.mint.opacity(0.25)), in: .capsule)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func consume() async {
        do {
            for try await event in events {
                withAnimation(.smooth) { apply(event) }
                switch event {
                case let .questionsNeeded(questions): onQuestions(questions)
                case let .completed(result): onComplete(result)
                default: break
                }
            }
        } catch is CancellationError {
            return
        } catch {
            onFailure(error)
        }
    }

    private func apply(_ event: PipelineEvent) {
        progress.apply(event)
        switch event {
        case let .componentsIdentified(identified): components = identified
        case let .metricResolved(_, _, tier): tierCounts[tier, default: 0] += 1
        case let .warning(message): lastWarning = message
        default: break
        }
    }
}

#Preview {
    let coordinator = ScanCoordinator(services: .demo(latency: .milliseconds(700)), profile: .default, mode: .photo)
    ZStack {
        LinearGradient(colors: [Theme.moss, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        AnalyzingCard(events: coordinator.scan(image: Data(), hints: .none),
                      onComplete: { print("done", $0.title) },
                      onFailure: { print($0) })
            .padding()
    }
}
