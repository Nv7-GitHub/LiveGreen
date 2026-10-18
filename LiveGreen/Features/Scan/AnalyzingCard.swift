import SwiftUI
import GreenCore
import GreenCoreFakes

/// Glass progress card for the analyzing state (spec §10). It consumes the coordinator's event stream
/// itself, so the steps, identified items and per-tier counts reflect real pipeline progress.
struct AnalyzingCard: View {
    let events: AsyncThrowingStream<PipelineEvent, Error>
    var onQuestions: ([PendingQuestion]) -> Void = { _ in }
    /// Detail questions for T4 items, delivered before `onComplete`.
    var onSpecQuestions: ([SpecQuestion]) -> Void = { _ in }
    let onComplete: (ScanResult) -> Void
    let onFailure: (Error) -> Void

    @State private var progress = PipelineProgress()
    @State private var components: [Component] = []
    @State private var tierCounts: [Tier: Int] = [:]
    @State private var lastWarning: String?
    /// Item names streamed from the vision model before identification finishes.
    @State private var spotted: [String] = []
    @State private var writtenCharacters = 0
    @State private var identifyStart: Date?

    var body: some View {
        // Tinted toward the system background so the text keeps its contrast over a dark or busy photo.
        GlassCard(tint: Color(uiColor: .systemBackground).opacity(0.6)) {
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
                    if step == .identifying {
                        if isIdentifying { liveStatus }
                        if !itemNames.isEmpty { itemChips }
                    }
                }
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
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    /// Live counts next to each step: items found, then metrics resolved at that step's tiers.
    private func detail(for step: PipelineStep) -> String? {
        let count: Int
        switch step {
        case .readingLabels: return nil
        case .identifying:
            return components.isEmpty ? nil : "\(components.count) item\(components.count == 1 ? "" : "s")"
        case .lookingUpRecords: count = tierCounts[.exactRecord, default: 0]
        case .researchingSpecs: count = tierCounts[.researchedSpec, default: 0]
        case .computing: count = tierCounts[.factorModel, default: 0] + tierCounts[.estimate, default: 0]
        }
        return count > 0 ? "\(count) values" : nil
    }

    private var isIdentifying: Bool {
        progress.started.contains(.identifying) && !progress.finished.contains(.identifying)
    }

    /// While the model answers: what it is doing and a seconds counter. The line swaps its text without animating,
    /// so an old and a new status never draw over each other mid-transition.
    private var liveStatus: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let elapsed = identifyStart.map { context.date.timeIntervalSince($0) } ?? 0
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles").symbolEffect(.pulse)
                Text(statusText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(elapsed, format: .number.precision(.fractionLength(1))) s")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .transaction { $0.animation = nil }
        }
        .padding(.leading, 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liveIdentify")
    }

    private var statusText: String {
        if spotted.isEmpty { return writtenCharacters > 0 ? "Reading the photo…" : "Looking at the photo…" }
        return "Spotted \(spotted.count) item\(spotted.count == 1 ? "" : "s"), measuring…"
    }

    /// The items found so far: names as the model streams them, then the identified items in their place. Chips keep
    /// their position, so a name the final answer words differently ("Gray SUV (partial)" → "Grey SUV (partially
    /// visible)") reads as the same item updated, not a new one.
    private var itemNames: [(name: String, systemImage: String)] {
        components.isEmpty ? spotted.map { ($0, "eye") } : components.map { ($0.name, $0.category.systemImage) }
    }

    /// At most this many chips; the rest are counted in a last chip so the card stays short.
    private static let maxChips = 6

    private var itemChips: some View {
        let items = itemNames
        let shown = items.count > Self.maxChips ? Array(items.prefix(Self.maxChips - 1)) : items
        return WrappingChips(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                chip(item.name, systemImage: item.systemImage)
            }
            if shown.count < items.count {
                chip("+\(items.count - shown.count) more", systemImage: "ellipsis")
            }
        }
        .padding(.leading, 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("identifiedItems")
    }

    /// A plain tinted capsule: glass chips on the glass card merged into blurred blobs and drew over the next row.
    private func chip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.mint.opacity(0.3), in: .capsule)
            .transition(.opacity)
    }

    private func consume() async {
        do {
            for try await event in events {
                withAnimation(.smooth) { apply(event) }
                switch event {
                case let .questionsNeeded(questions): onQuestions(questions)
                case let .specQuestionsNeeded(questions): onSpecQuestions(questions)
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
        case .stepStarted(.identifying): identifyStart = .now
        case let .identifyProgress(update):
            spotted = update.itemNames
            writtenCharacters = update.receivedCharacters
        case let .componentsIdentified(identified): components = identified
        case let .metricResolved(_, _, tier): tierCounts[tier, default: 0] += 1
        case let .warning(message): lastWarning = message
        default: break
        }
    }
}

/// Lays chips out in rows, wrapping before the card's edge; a chip wider than a whole row is truncated to fit
/// rather than clipped.
private struct WrappingChips: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            let fitted = CGSize(width: min(size.width, width), height: size.height)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + fitted.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + fitted.width
            row.height = max(row.height, fitted.height)
            row.indices.append(index)
            row.sizes.append(fitted)
            rows[rows.count - 1] = row
        }
        return rows
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
