import SwiftUI
import GreenCore

/// All gated questions in one glass sheet (spec §5.5): chip answers per question plus a "Custom" chip with
/// a slider over the field's full range, "Use estimate" to keep the current ranges, or "Update numbers" to
/// re-run the engine with the answers.
struct QuestionsSheet: View {
    let questions: [PendingQuestion]
    let onApply: ([QuestionAnswer]) -> Void
    let onUseEstimate: () -> Void

    @State private var picks: [PendingQuestion.ID: AnswerOption] = [:]
    @State private var customValues: [PendingQuestion.ID: Double] = [:]

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
                if let field = Self.field(of: pending) { customChip(field, for: pending) }
            }
            .padding(.top, 4)
            if let field = Self.field(of: pending), let value = customValues[pending.id] {
                customSlider(field, value: value, for: pending)
            }
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

    /// The usage field a question's options set, when they all set the same one.
    private static func field(of pending: PendingQuestion) -> UsageField? {
        let fields = Set(pending.question.options.compactMap(\.field))
        return fields.count == 1 ? fields.first : nil
    }

    private func customChip(_ field: UsageField, for pending: PendingQuestion) -> some View {
        let isActive = customValues[pending.id] != nil
        return Button {
            withAnimation(.snappy) {
                if isActive {
                    customValues[pending.id] = nil
                    picks[pending.id] = nil
                } else {
                    let start = pending.question.options.compactMap(\.value).max() ?? field.customRange.lowerBound
                    setCustom(min(max(start, field.customRange.lowerBound), field.customRange.upperBound),
                              field: field, for: pending)
                }
            }
        } label: {
            Label("Custom", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(isActive ? .regular.tint(Theme.leaf.opacity(0.6)).interactive() : .regular.interactive(),
                     in: .capsule)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("customAnswer")
    }

    private func customSlider(_ field: UsageField, value: Double, for pending: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.customLabel(value))
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Slider(value: Binding(get: { value }, set: { setCustom($0, field: field, for: pending) }),
                   in: field.customRange, step: field.customStep) {
                Text("Custom answer")
            } minimumValueLabel: {
                Text(Measured.format(field.customRange.lowerBound)).font(.caption2)
            } maximumValueLabel: {
                Text(Measured.format(field.customRange.upperBound)).font(.caption2)
            }
            .tint(Theme.leaf)
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func setCustom(_ value: Double, field: UsageField, for pending: PendingQuestion) {
        customValues[pending.id] = value
        picks[pending.id] = AnswerOption(label: field.customLabel(value), field: field, value: value)
    }

    private func chip(_ option: AnswerOption, for pending: PendingQuestion) -> some View {
        let isPicked = picks[pending.id] == option && customValues[pending.id] == nil
        return Button {
            withAnimation(.snappy) {
                customValues[pending.id] = nil
                picks[pending.id] = isPicked ? nil : option
            }
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
