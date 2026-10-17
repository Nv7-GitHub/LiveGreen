import SwiftUI
import GreenCore

/// All gated questions in one glass sheet (spec §5.5): chip answers per question, "Use estimate" to
/// keep the current ranges, or "Update numbers" to re-run the engine with the answers.
struct QuestionsSheet: View {
    let questions: [PendingQuestion]
    let onApply: ([QuestionAnswer]) -> Void
    let onUseEstimate: () -> Void

    @State private var picks: [PendingQuestion.ID: AnswerOption] = [:]

    private var answers: [QuestionAnswer] {
        questions.compactMap { question in picks[question.id].map { QuestionAnswer(question: question, option: $0) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("A quick answer narrows the widest ranges in this scan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(questions) { question in
                        questionCard(question)
                    }
                }
                .padding()
            }
            .navigationTitle(questions.count == 1 ? "One question" : "\(questions.count) questions")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actions }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func questionCard(_ pending: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pending.componentName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(pending.question.question).font(.headline)
            Text(pending.question.whyItMatters).font(.footnote).foregroundStyle(.secondary)
            ChipLayout(spacing: 8) {
                ForEach(Array(pending.question.options.enumerated()), id: \.offset) { _, option in
                    chip(option, for: pending)
                }
            }
            .padding(.top, 4)
            if !pending.question.affectedMetrics.isEmpty {
                Label("Affects " + pending.question.affectedMetrics.map { $0.displayName.lowercased() }
                    .joined(separator: ", "), systemImage: "scope")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }

    private func chip(_ option: AnswerOption, for pending: PendingQuestion) -> some View {
        let isPicked = picks[pending.id] == option
        return Button {
            withAnimation(.snappy) { picks[pending.id] = isPicked ? nil : option }
        } label: {
            Text(option.label)
                .font(.subheadline.weight(isPicked ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isPicked ? .regular.tint(Theme.leaf.opacity(0.6)).interactive() : .regular.interactive(),
                     in: .capsule)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("Use estimate", action: onUseEstimate)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("useEstimate")
                Button("Update numbers", systemImage: "arrow.triangle.2.circlepath") { onApply(answers) }
                    .buttonStyle(.glassProminent)
                    .disabled(answers.isEmpty)
                    .accessibilityIdentifier("applyAnswers")
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

/// Wraps chips onto as many rows as needed.
private struct ChipLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
