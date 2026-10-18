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
    /// Per-item yearly values, shares, ranks and pin numbers for `current`, so rows, pins and the summary share one
    /// basis with the per-year headline.
    @State private var breakdown: ScanBreakdown
    @State private var filter: ResultMetricFilter = .carbon
    @State private var selectedID: Component.ID?
    @State private var showsQuestions = false
    @State private var handledQuestions: Set<PendingQuestion.ID> = []
    @State private var didOfferQuestions = false
    @State private var isRerunning = false
    /// Height of the overview's visible area, which caps the photo's height.
    @State private var viewportHeight: CGFloat = 0

    /// - Parameter rerun: overrides the default local impact-engine re-run.
    init(result: ScanResult, rerun: Rerun? = nil) {
        self.result = result
        self.rerun = rerun
        _current = State(initialValue: result)
        _breakdown = State(initialValue: ScanBreakdown(components: result.components))
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
                // Content scrolled under the Done button is cut off cleanly instead of showing through behind it.
                .scrollEdgeEffectStyle(.hard, for: .top)
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
        .onChange(of: current.components) { _, components in
            withAnimation(.smooth) { breakdown = ScanBreakdown(components: components) }
        }
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    photo
                    MetricPicker(selection: $filter, options: availableFilters)
                    SummaryHeader(result: current, filter: filter, breakdown: breakdown)
                    if !pendingQuestions.isEmpty { questionsBanner }
                    componentList
                    alternativesButton
                    ScanFeedbackCard(result: current)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .animation(.smooth, value: current)
                .animation(.smooth, value: filter)
            }
            .scrollIndicators(.hidden)
            // Room for the floating tab bar so the last rows and the swaps button are never covered.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .onChange(of: selectedID) { _, id in
                // In portrait the detail sheet covers the lower half of the screen: bring the selected item into the
                // part above it, wherever it was tapped from.
                guard id != nil, !isLandscape else { return }
                Task { @MainActor in
                    withAnimation(.smooth) { proxy.scrollTo(Self.selectionAnchorID, anchor: UnitPoint(x: 0.5, y: 0.3)) }
                }
            }
        }
    }

    /// Tall photos are capped so the picker and headline stay on the first screen: about half the visible height in
    /// portrait, most of it in landscape.
    private var photoMaxHeight: CGFloat {
        guard viewportHeight > 0 else { return 420 }
        return isLandscape ? max(200, viewportHeight * 0.8) : min(max(viewportHeight * 0.5, 260), 480)
    }

    private var photo: some View {
        ResultPhoto(data: current.photo, mode: current.mode, maxHeight: photoMaxHeight) {
            // A barcode scan's photo is the product's own pack shot, not the scene, so there is
            // nothing to point at.
            if current.mode != .barcode {
                ZStack {
                    ComponentHotspots(components: shownComponents, filter: filter, breakdown: breakdown,
                                      selectedID: selectedID, onSelect: select)
                    selectionAnchor
                }
            }
        }
        .clipShape(.rect(cornerRadius: Theme.cardCornerRadius))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private static let selectionAnchorID = "selectedItemAnchor"

    /// An invisible point at the selected item's box center, scrolled to when an item is selected.
    private var selectionAnchor: some View {
        GeometryReader { geometry in
            let box = selectedComponent?.boundingBox.clamped ?? .full
            Color.clear
                .frame(width: 1, height: 1)
                .position(x: box.midX * geometry.size.width, y: box.midY * geometry.size.height)
                .id(Self.selectionAnchorID)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var componentList: some View {
        let metric = filter.shareMetric
        let ranked = breakdown.ranked(shownComponents, by: metric)
        let engine = ImpactEngine()
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter == .all ? "Items" : "Items by \(filter.title.lowercased())")
                    .font(.headline)
                Text("Color shows each item's yearly amount next to a typical person's year")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            VStack(spacing: 0) {
                // Numbers are the pins' (by yearly carbon), so they stay with their items when the metric changes.
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, component in
                    if index > 0 { Divider().padding(.leading, 54) }
                    let yearly = breakdown.yearly(metric, of: component)
                    Button { select(component) } label: {
                        ComponentRow(component: component, number: breakdown.number(of: component), filter: filter,
                                     yearly: yearly,
                                     share: breakdown.share(of: component, metric: metric, in: shownComponents),
                                     assumption: ResultInsights.assumptionLabel(for: component, metric: metric,
                                                                                breakdown: breakdown, engine: engine),
                                     tint: Theme.impactTint(ImpactLevel(yearly: yearly?.value ?? 0, metric: metric)),
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
            ?? breakdown.ranked(current.components, by: .carbon).first
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
            var updated = rebasingSwaps(from: base, onto: await (rerun ?? localRerun)(base, answers))
            updated.components = QuestionGate.settling(settled, in: updated.components)
            withAnimation(.smooth) { current = updated }
            model.save(updated)
            isRerunning = false
        }
    }

    /// Usage edited in the detail sheet: re-run the engine on-device and save.
    private func applyUsage(_ field: UsageField, _ value: Double, to componentID: UUID) {
        let base = savedCopy ?? current
        let updated = rebasingSwaps(from: base,
                                    onto: model.makeScanCoordinator().applying(usage: field, value: value,
                                                                               to: componentID, in: base))
        withAnimation(.smooth) { current = updated }
        model.save(updated)
    }

    /// Saved swaps take the new usage too (`SwapPrefetcher.rebase`), so the swaps screen still compares like with like.
    private func rebasingSwaps(from base: ScanResult, onto updated: ScanResult) -> ScanResult {
        guard base.hasAlternatives else { return updated }
        return SwapPrefetcher.rebase(base, onto: updated, engine: ImpactEngine(reference: model.services.reference),
                                     profile: model.profile)
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
