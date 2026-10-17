import SwiftUI
import GreenCore

/// Shown before the results when some items are still rough AI estimates (T4): one plain question per item as
/// chips plus "Not sure". "Update numbers" re-resolves the answered items on-device with the factor tables;
/// "Skip" (or swiping the sheet away) opens the results with the estimates.
struct SpecQuestionsSheet: View {
    let questions: [SpecQuestion]
    let onApply: ([SpecAnswer]) -> Void
    let onSkip: () -> Void

    @State private var picks: [SpecQuestion.ID: SpecOption] = [:]
    @State private var notSure: Set<SpecQuestion.ID> = []
    @State private var isApplying = false
    @State private var detent: PresentationDetent

    init(questions: [SpecQuestion], onApply: @escaping ([SpecAnswer]) -> Void, onSkip: @escaping () -> Void) {
        self.questions = questions
        self.onApply = onApply
        self.onSkip = onSkip
        _detent = State(initialValue: questions.count > 1 ? .large : .medium)
    }

    private var answers: [SpecAnswer] {
        questions.compactMap { question in
            picks[question.id].map { SpecAnswer(componentID: question.componentID, option: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("A couple of quick details to sharpen the numbers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(questions) { questionCard($0) }
                }
                .padding()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("specQuestions")
            }
            .navigationTitle("Quick details")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actions }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private func questionCard(_ question: SpecQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.componentName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(question.question).font(.headline)
            ChipLayout(spacing: 8) {
                ForEach(question.options) { option in
                    chip(option.label, isPicked: picks[question.id] == option) {
                        notSure.remove(question.id)
                        picks[question.id] = picks[question.id] == option ? nil : option
                    }
                    .accessibilityIdentifier("specOption.\(option.label)")
                }
                chip("Not sure", isPicked: notSure.contains(question.id)) {
                    picks[question.id] = nil
                    if notSure.remove(question.id) == nil { notSure.insert(question.id) }
                }
                .accessibilityIdentifier("specOption.notSure")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .contain)
    }

    private func chip(_ label: String, isPicked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(label)
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
                Button("Skip", action: onSkip)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("specSkip")
                Button("Update numbers", systemImage: "arrow.triangle.2.circlepath") {
                    isApplying = true
                    onApply(answers)
                }
                .buttonStyle(.glassProminent)
                .disabled(answers.isEmpty || isApplying)
                .accessibilityIdentifier("specApply")
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

#Preview {
    let box = Component(name: "Takeout box", category: .packaging)
    Color.clear.sheet(isPresented: .constant(true)) {
        SpecQuestionsSheet(questions: SpecQuestionCatalog.candidates(for: box, store: .bundled),
                           onApply: { print($0) }, onSkip: {})
    }
}
