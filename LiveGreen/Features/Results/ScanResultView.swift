import SwiftUI
import GreenCore
import GreenCoreFakes

/// Results for one scan (spec §6): summary header with confidence, the photo with glass hotspots,
/// a glass metric picker and the component list. Tapping a component opens its flow + inspector in a
/// detent sheet (portrait) or a side inspector (landscape). Gated questions (spec §5.5) appear in one
/// sheet and re-run the engine locally.
struct ScanResultView: View {
    /// Re-runs the engine with question answers and returns the updated result.
    typealias Rerun = @MainActor (ScanResult, [QuestionAnswer]) async -> ScanResult

    let result: ScanResult
    private let rerun: Rerun?

    @Environment(AppModel.self) private var model
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var current: ScanResult
    @State private var filter: ResultMetricFilter = .carbon
    @State private var selectedID: Component.ID?
    @State private var showsQuestions = false
    @State private var handledQuestions: Set<PendingQuestion.ID> = []
    @State private var didOfferQuestions = false
    @State private var isRerunning = false

    /// - Parameter rerun: overrides the default local `UsageRecalculator` re-run.
    init(result: ScanResult, rerun: Rerun? = nil) {
        self.result = result
        self.rerun = rerun
        _current = State(initialValue: result)
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var pendingQuestions: [PendingQuestion] {
        QuestionGate.pendingQuestions(for: current.components).filter { !handledQuestions.contains($0.id) }
    }

    private var selectedComponent: Component? { selectedID.flatMap(current.component(withID:)) }

    var body: some View {
        Group {
            if isLandscape {
                HStack(alignment: .top, spacing: 0) {
                    overview
                    sideInspector
                }
            } else {
                overview
            }
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AlternativesView(result: current)
                } label: {
                    Label("Greener swaps", systemImage: "leaf.arrow.triangle.circlepath")
                }
            }
        }
        .sheet(item: sheetSelection) { component in
            NavigationStack {
                ScrollView {
                    detail(for: component).padding()
                }
                .navigationTitle(component.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", systemImage: "checkmark") { selectedID = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showsQuestions) {
            QuestionsSheet(questions: pendingQuestions, onApply: applyAnswers, onUseEstimate: useEstimates)
        }
        .onChange(of: result) { _, newValue in current = newValue }
        .task { await offerQuestionsOnce() }
    }

    // MARK: - Overview

    private var overview: some View {
        ScrollView {
            VStack(spacing: 16) {
                SummaryHeader(result: current, filter: filter)
                photo
                MetricPicker(selection: $filter)
                if !pendingQuestions.isEmpty { questionsBanner }
                componentList
                alternativesButton
            }
            .padding()
            .animation(.smooth, value: current)
        }
        .scrollIndicators(.hidden)
    }

    private var photo: some View {
        ResultPhoto(data: current.photo)
            .overlay {
                ComponentHotspots(components: current.components, filter: filter,
                                  selectedID: selectedID, onSelect: select)
            }
            .clipShape(.rect(cornerRadius: Theme.cardCornerRadius))
            .accessibilityIdentifier("resultPhoto")
    }

    private var componentList: some View {
        let ranked = ResultInsights.ranked(current.components, by: filter.shareMetric)
        return VStack(spacing: 10) {
            ForEach(ranked) { component in
                Button { select(component) } label: {
                    ComponentRow(component: component, filter: filter,
                                 share: ResultInsights.share(of: component, metric: filter.shareMetric,
                                                             in: current.components),
                                 isSelected: component.id == selectedID)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var questionsBanner: some View {
        Button { showsQuestions = true } label: {
            HStack(spacing: 12) {
                Image(systemName: isRerunning ? "hourglass" : "questionmark.bubble")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pendingQuestions.count == 1 ? "1 question can narrow these numbers"
                                                     : "\(pendingQuestions.count) questions can narrow these numbers")
                        .font(.subheadline.weight(.semibold))
                    Text("Answer to tighten the widest ranges.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .glassCard(cornerRadius: 20, tint: Theme.warning.opacity(0.18), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("questionsBanner")
    }

    private var alternativesButton: some View {
        NavigationLink {
            AlternativesView(result: current)
        } label: {
            Label("See greener swaps", systemImage: "leaf.arrow.triangle.circlepath")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .accessibilityIdentifier("openAlternatives")
    }

    // MARK: - Detail

    /// Landscape: the inspector sits beside the overview (spec §6), showing the selection or the top
    /// carbon contributor.
    private var sideInspector: some View {
        let component = selectedComponent
            ?? ResultInsights.ranked(current.components, by: .carbon).first
        return ScrollView {
            if let component {
                detail(for: component).padding()
            } else {
                ContentUnavailableView("No items", systemImage: "square.dashed")
            }
        }
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .padding([.vertical, .trailing])
    }

    private func detail(for component: Component) -> some View {
        var plugAction: (() -> Void)?
        if model.flags.plugFeaturesEnabled { plugAction = { openPlugs() } }
        return ComponentDetailView(component: component, preferredMetric: filter.shareMetric, plugAction: plugAction)
            .id(component.id)
    }

    /// The portrait sheet follows the selection; in landscape the side inspector shows it instead.
    private var sheetSelection: Binding<Component?> {
        Binding(
            get: { isLandscape ? nil : selectedComponent },
            set: { newValue in
                if !isLandscape { selectedID = newValue?.id }
            })
    }

    private func select(_ component: Component) {
        withAnimation(.smooth) { selectedID = component.id }
    }

    private func openPlugs() {
        selectedID = nil
        model.selectedTab = .plugs
    }

    // MARK: - Questions

    private func offerQuestionsOnce() async {
        guard !didOfferQuestions else { return }
        didOfferQuestions = true
        // Let the navigation push settle before presenting.
        try? await Task.sleep(for: .milliseconds(450))
        if !pendingQuestions.isEmpty { showsQuestions = true }
    }

    private func useEstimates() {
        handledQuestions.formUnion(pendingQuestions.map(\.id))
        showsQuestions = false
    }

    private func applyAnswers(_ answers: [QuestionAnswer]) {
        handledQuestions.formUnion(pendingQuestions.map(\.id))
        showsQuestions = false
        isRerunning = true
        Task {
            let updated = await (rerun ?? localRerun)(current, answers)
            withAnimation(.smooth) { current = updated }
            model.save(updated)
            isRerunning = false
        }
    }

    /// Default re-run: deterministic, on-device, using the region's grid intensity.
    private func localRerun(_ result: ScanResult, _ answers: [QuestionAnswer]) async -> ScanResult {
        let reference = model.services.reference
        let gramsPerKWh = model.profile.gridLookupKeys.lazy
            .compactMap { reference.gridIntensity(region: $0)?.annualAverageGPerKWh }
            .first ?? Self.fallbackGridGramsPerKWh
        return UsageRecalculator(gridKgPerKWh: gramsPerKWh / 1000).apply(answers, to: result)
    }

    /// Approximate world-average grid intensity, used only when no regional figure is bundled.
    private static let fallbackGridGramsPerKWh = 475.0
}

#Preview("Desk setup") {
    NavigationStack { ScanResultView(result: ResultSamples.desk) }
        .environment(AppModel.preview())
}

#Preview("Lunch (estimates)") {
    NavigationStack { ScanResultView(result: SampleScans.preview(.meal)) }
        .environment(AppModel.preview())
}
