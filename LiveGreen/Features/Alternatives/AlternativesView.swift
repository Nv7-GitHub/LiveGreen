import SwiftUI
import GreenCore
import GreenCoreFakes

/// Take action: each item's greener swap as a plan to carry out (the nearby place to get it, with directions, and
/// steps to tick off), then the projected yearly savings and, for scenes of more than two items, a picture of the
/// greener setup. The swap picker and like-for-like chart (spec §7) sit inside each card.
struct AlternativesView: View {
    /// Read in `body` so converted numbers refresh when Settings switches units.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
    @Environment(AppModel.self) private var app
    @State private var screen: AlternativesModel
    @Namespace private var glass

    init(result: ScanResult) {
        _screen = State(initialValue: AlternativesModel(result: result))
    }

    private var plugFeatures: Bool { app.flags.plugFeaturesEnabled }

    var body: some View {
        let _ = unitSystem
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 16) {
                    switch screen.phase {
                    case .pending:
                        EmptyView()
                    case .loading:
                        loadingCard
                    case let .failed(message):
                        failureCard(message)
                    case .ready where !hasSwaps:
                        noSwapsCard
                    case .ready:
                        planSummary
                        swapCards
                        if !itemsWithoutSwaps.isEmpty { noOptionCard }
                        ProjectedSavingsCard(savings: SwapMath.projectedSavings(screen.result, selection: selection),
                                             swapCount: selection.count,
                                             context: "swaps-\(screen.result.id.uuidString)")
                        if screen.showsGreenerImage { imageSection.id(Self.imageAnchor) }
                        if screen.result.isScreenshot {
                            Label("No greener picture for a screenshot: it would redraw someone else's post.",
                                  systemImage: "photo.badge.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("alternatives.noImageForScreenshot")
                        }
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                if screen.phase == .ready, hasSwaps, screen.showsGreenerImage { generateBar }
            }
            // The image section is empty until generation starts, so scroll once it has content. Its top goes to the
            // top of the view: aligning its bottom pushed a tall photo's "Before" tag under the navigation bar (G3).
            .onChange(of: screen.imageState) { _, state in
                guard state != .idle else { return }
                withAnimation { scroller.scrollTo(Self.imageAnchor, anchor: .top) }
            }
        }
        .navigationTitle("Take action")
        .task { await screen.load(app: app) }
        .task(id: planKey) { await makePlans() }
    }

    private static let imageAnchor = "greenerImage"

    private var selection: [UUID: UUID] { screen.visibleSelection(plugFeatures: plugFeatures) }

    private var hasSwaps: Bool {
        screen.result.components.contains { !screen.alternatives(for: $0, plugFeatures: plugFeatures).isEmpty }
    }

    // MARK: - Sections

    private var loadingCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading) {
                    Text("Finding greener swaps…").font(.headline)
                    Text("Each swap is checked with the same evidence ladder as your items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var noSwapsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("No lower-impact option found", systemImage: "leaf").font(.headline)
                Text("Every swap we checked made at least one thing a lot worse, or was the same item under another name, so none is suggested.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("alternatives.none")
    }

    /// Items with nothing to offer, biggest yearly carbon first, so the main item is never silently missing (S10:
    /// the camera was 92% of the scene and had no card).
    private var itemsWithoutSwaps: [Component] {
        screen.result.totaledComponents
            .filter { screen.alternatives(for: $0, plugFeatures: plugFeatures).isEmpty }
            .sorted { (SwapMath.yearlyCarbon(of: $0)?.value ?? 0) > (SwapMath.yearlyCarbon(of: $1)?.value ?? 0) }
    }

    private var noOptionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("No lower-impact option found", systemImage: "leaf").font(.headline)
                ForEach(itemsWithoutSwaps) { component in
                    Label(component.name, systemImage: component.category.systemImage)
                        .font(.subheadline)
                }
                Text("We looked for swaps for these too, but none was clearly better without making something else worse.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("alternatives.noOption")
    }

    private func failureCard(_ message: String) -> some View {
        GlassCard(tint: Theme.danger.opacity(0.15)) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't load swaps", systemImage: "exclamationmark.triangle").font(.headline)
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Try again", systemImage: "arrow.clockwise") { Task { await screen.load(app: app) } }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    /// Biggest yearly saving first (`SwapMath.byYearlySaving`), not the order items were spotted in; items offered
    /// the same swaps share a card (`AlternativesModel.swapGroups`).
    @ViewBuilder private var swapCards: some View {
        let ordered = SwapMath.byYearlySaving(screen.result.components) {
            screen.alternatives(for: $0, plugFeatures: plugFeatures)
        }
        ForEach(AlternativesModel.swapGroups(ordered, plugFeatures: plugFeatures), id: \.first?.id) { group in
            let component = group[0]
            let others = Array(group.dropFirst())
            let options = screen.alternatives(for: component, plugFeatures: plugFeatures)
            let pick = selection[component.id].flatMap { id in options.first { $0.id == id } }
            let plans = app.actionPlans
            ActionCard(component: component, others: others, alternatives: options, pick: pick,
                       charging: screen.charging[component.id],
                       plan: pick.flatMap(plans.plan(for:)),
                       isPlanning: pick.map { plans.planning.contains($0.id) } ?? false,
                       isDone: plans.isDone, onToggle: plans.toggle,
                       onChoosePlace: { place in
                           guard let pick else { return }
                           Task { await plans.choose(place, for: pick, replacing: component, app: app) }
                       },
                       onSelect: { screen.toggle($0, for: component, others: others, app: app) },
                       onPair: { app.selectedTab = .plugs })
        }
    }

    // MARK: - Action plans

    /// The lead item and pick of every card, so plans are made again when a pick changes.
    private var picked: [(component: Component, swap: Alternative)] {
        let ordered = SwapMath.byYearlySaving(screen.result.components) {
            screen.alternatives(for: $0, plugFeatures: plugFeatures)
        }
        return AlternativesModel.swapGroups(ordered, plugFeatures: plugFeatures).compactMap { group in
            let lead = group[0]
            let options = screen.alternatives(for: lead, plugFeatures: plugFeatures)
            return selection[lead.id].flatMap { id in options.first { $0.id == id } }.map { (lead, $0) }
        }
    }

    private var planKey: String {
        screen.phase == .ready ? picked.map(\.swap.id.uuidString).joined(separator: ",") : ""
    }

    /// Plans for every pick at once; saved plans come back immediately.
    private func makePlans() async {
        guard screen.phase == .ready else { return }
        let plans = app.actionPlans
        await withTaskGroup(of: Void.self) { group in
            for (component, swap) in picked {
                group.addTask { await plans.ensurePlan(for: swap, replacing: component, app: app) }
            }
        }
    }

    /// How many actions there are, how far along they are and what they save together.
    private var planSummary: some View {
        let plans = app.actionPlans
        let actions = picked
        let steps = actions.compactMap { plans.progress(for: $0.swap) }
        let done = steps.map(\.done).reduce(0, +)
        let total = steps.map(\.total).reduce(0, +)
        let saving = SwapMath.projectedSavings(screen.result, selection: selection)[.carbon]?.yearly?.value ?? 0
        return GlassCard(tint: Theme.leaf.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Your game plan", systemImage: "checklist").font(.headline).foregroundStyle(Theme.leaf)
                Text(actions.isEmpty ? "Pick a swap below to get steps and a place nearby."
                     : "\(actions.count) \(actions.count == 1 ? "action" : "actions") near you"
                        + (saving > 0 ? ", saving about \(DisplayUnits.carbon(kg: saving)) a year" : ""))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total)).tint(Theme.leaf)
                    Text("\(done) of \(total) steps done").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("alternatives.summary")
    }

    @ViewBuilder private var imageSection: some View {
        if let photo = screen.result.photo, !photo.isEmpty {
            let boxes = GreenerImagePrompt.swaps(for: screen.result, selection: selection).compactMap(\.boundingBox)
            GreenerImageView(original: photo, state: screen.imageState,
                             reveal: GreenerImagePrompt.revealSplit(for: boxes)) { generate() }
        } else {
            Label("This scan has no photo, so a greener picture can't be generated. The comparison above still applies.",
                  systemImage: "photo.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Generates the picture, or once it is on screen offers another version (G1). Picks that would not show in a
    /// photo (the plug, a used copy of the same item) leave nothing to draw, and the bar says so.
    private var generateBar: some View {
        let swaps = GreenerImagePrompt.swaps(for: screen.result, selection: selection)
        let generating = screen.imageState == .generating
        let title = generating ? "Generating…" : screen.hasImage ? "Regenerate greener setup" : "Generate greener setup"
        return GlassEffectContainer {
            VStack(spacing: 6) {
                if swaps.isEmpty, screen.hasPhoto {
                    Text(selection.isEmpty ? "Pick a swap to picture your greener setup."
                                           : "None of the picked swaps would look different in a photo.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                }
                Button {
                    generate()
                } label: {
                    Label(title, systemImage: screen.hasImage ? "arrow.clockwise" : "wand.and.sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!screen.hasPhoto || swaps.isEmpty || generating)
                .glassEffectID("generate", in: glass)
                .accessibilityIdentifier("alternatives.generate")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// A second tap asks for a new edit rather than the one already shown.
    private func generate() {
        let fresh = screen.hasImage
        Task { await screen.generateImage(app: app, fresh: fresh) }
    }
}

#Preview("Desk swaps") {
    NavigationStack { AlternativesView(result: AlternativesPreviewData.result) }
        .environment(AppModel.preview())
}

#Preview("Resolving") {
    NavigationStack { AlternativesView(result: SampleScans.preview(.eBikeCorner)) }
        .environment(AppModel.preview())
}
