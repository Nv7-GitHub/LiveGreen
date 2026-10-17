import SwiftUI
import GreenCore
import GreenCoreFakes

/// Results for one scan (spec §6): summary header with confidence, the photo with glass hotspots,
/// a glass metric picker and the component list. Tapping a component opens its flow + inspector in a
/// detent sheet (portrait) or a side inspector (landscape). Gated questions (spec §5.5) appear in one
/// sheet and re-run the engine locally.
struct ScanResultView: View {
    /// Read in `body` so converted numbers refresh when Settings switches units.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
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

    /// - Parameter rerun: overrides the default local impact-engine re-run.
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

    private var availableFilters: [ResultMetricFilter] { ResultInsights.availableFilters(for: current.components) }

    /// The components that have the selected metric; a laptop has no land use, so it leaves the Land view.
    private var shownComponents: [Component] { ResultInsights.components(current.components, showing: filter) }

    var body: some View {
        let _ = unitSystem
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
                // The detail header already names the item.
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
        .onChange(of: availableFilters, initial: true) { _, options in
            if !options.contains(filter) { filter = options.first ?? .carbon }
        }
        // Greener swaps save picks and the image to the stored scan; pick them up when returning here.
        .onAppear { if let saved = savedCopy, saved != current { current = saved } }
        .onAppear { model.prefetchSwaps(for: current) }
        .task { await offerQuestionsOnce() }
    }

    // MARK: - Overview

    private var overview: some View {
        ScrollView {
            VStack(spacing: 14) {
                photo
                MetricPicker(selection: $filter, options: availableFilters)
                SummaryHeader(result: current, filter: filter)
                if !pendingQuestions.isEmpty { questionsBanner }
                componentList
                alternativesButton
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .animation(.smooth, value: current)
            .animation(.smooth, value: filter)
        }
        .scrollIndicators(.hidden)
        // Room for the floating tab bar so the last rows and the swaps button are never covered.
        .contentMargins(.bottom, 96, for: .scrollContent)
    }

    private var photo: some View {
        ResultPhoto(data: current.photo, mode: current.mode)
            // On the photo itself: on the container it would replace every hotspot's identifier.
            .accessibilityIdentifier("resultPhoto")
            .overlay {
                // A barcode scan's photo is the product's own pack shot, not the scene, so there is
                // nothing to point at.
                if current.mode != .barcode {
                    ComponentHotspots(components: shownComponents, filter: filter,
                                      selectedID: selectedID, onSelect: select)
                }
            }
            .clipShape(.rect(cornerRadius: Theme.cardCornerRadius))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private var componentList: some View {
        let ranked = ResultInsights.ranked(shownComponents, by: filter.shareMetric)
        return VStack(alignment: .leading, spacing: 6) {
            Text(filter == .all ? "Items" : "Items by \(filter.title.lowercased())")
                .font(.headline)
                .padding(.horizontal, 6)
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, component in
                    if index > 0 { Divider().padding(.leading, 54) }
                    Button { select(component) } label: {
                        ComponentRow(component: component, number: index + 1, filter: filter,
                                     share: ResultInsights.share(of: component, metric: filter.shareMetric,
                                                                 in: shownComponents),
                                     isSelected: component.id == selectedID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        }
        .padding(.top, 4)
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
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
        return ComponentDetailView(component: component, preferredMetric: filter.shareMetric, plugAction: plugAction,
                                   onUsageChange: { field, value in applyUsage(field, value, to: component.id) })
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
        let declined = pendingQuestions
        handledQuestions.formUnion(declined.map(\.id))
        showsQuestions = false
        var updated = savedCopy ?? current
        updated.components = QuestionGate.settling(declined, in: updated.components)
        current = updated
        model.save(updated)
    }

    /// The stored scan, which carries alternatives, picks and the greener image saved by the swaps screen.
    private var savedCopy: ScanResult? { model.scans.first { $0.id == current.id } }

    private func applyAnswers(_ answers: [QuestionAnswer]) {
        let settled = pendingQuestions
        handledQuestions.formUnion(settled.map(\.id))
        showsQuestions = false
        isRerunning = true
        Task {
            let base = savedCopy ?? current
            var updated = await (rerun ?? localRerun)(base, answers)
            updated.components = QuestionGate.settling(settled, in: updated.components)
            withAnimation(.smooth) { current = updated }
            model.save(updated)
            isRerunning = false
        }
    }

    /// Usage edited in the detail sheet: re-run the engine on-device and save.
    private func applyUsage(_ field: UsageField, _ value: Double, to componentID: UUID) {
        let base = savedCopy ?? current
        let updated = model.makeScanCoordinator().applying(usage: field, value: value, to: componentID, in: base)
        withAnimation(.smooth) { current = updated }
        model.save(updated)
    }

    /// Default re-run: GreenCore's impact engine, deterministic and on-device (spec §5.5).
    private func localRerun(_ result: ScanResult, _ answers: [QuestionAnswer]) async -> ScanResult {
        model.makeScanCoordinator().applying(answers, to: result)
    }
}

#Preview("Desk setup") {
    NavigationStack { ScanResultView(result: ResultSamples.desk) }
        .environment(AppModel.preview())
}

#Preview("Lunch (estimates)") {
    NavigationStack { ScanResultView(result: SampleScans.preview(.meal)) }
        .environment(AppModel.preview())
}
