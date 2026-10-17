import SwiftUI
import GreenCore
import GreenCoreFakes

/// Greener swaps per component (spec §7): pick one per component, compare like-for-like,
/// see projected yearly savings and generate a picture of the greener setup.
struct AlternativesView: View {
    @Environment(AppModel.self) private var app
    @State private var screen: AlternativesModel
    @Namespace private var glass

    init(result: ScanResult) {
        _screen = State(initialValue: AlternativesModel(result: result))
    }

    private var plugFeatures: Bool { app.flags.plugFeaturesEnabled }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 16) {
                    switch screen.phase {
                    case .loading:
                        loadingCard
                    case let .failed(message):
                        failureCard(message)
                    case .ready:
                        swapCards
                        ProjectedSavingsCard(savings: SwapMath.projectedSavings(screen.result, selection: selection),
                                             swapCount: selection.count)
                        imageSection.id(Self.imageAnchor)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                if screen.phase == .ready { generateBar }
            }
            // The image section is empty until generation starts, so scroll once it has content.
            .onChange(of: screen.imageState) { _, state in
                guard state != .idle else { return }
                withAnimation { scroller.scrollTo(Self.imageAnchor, anchor: .bottom) }
            }
        }
        .navigationTitle("Greener swaps")
        .task { await screen.load(app: app) }
    }

    private static let imageAnchor = "greenerImage"

    private var selection: [UUID: UUID] { screen.visibleSelection(plugFeatures: plugFeatures) }

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

    @ViewBuilder private var swapCards: some View {
        ForEach(screen.result.components) { component in
            let options = screen.alternatives(for: component, plugFeatures: plugFeatures)
            if !options.isEmpty {
                ComponentSwapCard(component: component, alternatives: options,
                                  pick: selection[component.id].flatMap { id in options.first { $0.id == id } },
                                  charging: screen.charging[component.id],
                                  onSelect: { screen.toggle($0, for: component, app: app) },
                                  onPair: { app.selectedTab = .plugs })
            }
        }
    }

    @ViewBuilder private var imageSection: some View {
        if let photo = screen.result.photo, !photo.isEmpty {
            GreenerImageView(original: photo, state: screen.imageState) { generate() }
        } else {
            Label("This scan has no photo, so a greener picture can't be generated. The comparison above still applies.",
                  systemImage: "photo.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var generateBar: some View {
        let swaps = GreenerImagePrompt.swaps(for: screen.result, selection: selection)
        let generating = screen.imageState == .generating
        return GlassEffectContainer {
            VStack(spacing: 6) {
                Button {
                    generate()
                } label: {
                    Label(generating ? "Generating…" : "Generate greener setup", systemImage: "wand.and.sparkles")
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

    private func generate() {
        Task { await screen.generateImage(app: app) }
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
