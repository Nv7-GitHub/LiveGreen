import SwiftUI
import GreenCore
import GreenCoreFakes

/// Greener swaps per component (spec §7): pick one per component, compare like-for-like,
/// see projected yearly savings and, for scenes of more than two items, generate a picture of the greener setup.
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
                        swapCards
                        if !itemsWithoutSwaps.isEmpty { noOptionCard }
                        ProjectedSavingsCard(savings: SwapMath.projectedSavings(screen.result, selection: selection),
                                             swapCount: selection.count,
                                             context: "swaps-\(screen.result.id.uuidString)")
                        if screen.showsGreenerImage { imageSection.id(Self.imageAnchor) }
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
        .navigationTitle("Greener swaps")
        .task { await screen.load(app: app) }
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
        screen.result.components
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
            ComponentSwapCard(component: component, others: others, alternatives: options,
                              pick: selection[component.id].flatMap { id in options.first { $0.id == id } },
                              charging: screen.charging[component.id],
                              onSelect: { screen.toggle($0, for: component, others: others, app: app) },
                              onPair: { app.selectedTab = .plugs })
        }
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
