import SwiftUI
import GreenCore

/// "Charging this only when the grid is clean would save ~X kg CO₂e/yr" card (spec §8.1).
/// Hidden when smart plug features are turned off in Settings.
struct PlugRecommendationCard: View {
    let component: Component
    let candidate: PlugCandidate
    private let onPair: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var estimate: Measured?
    @State private var showsPairing = false

    init(component: Component, candidate: PlugCandidate, onPair: @escaping () -> Void) {
        self.component = component
        self.candidate = candidate
        self.onPair = onPair
    }

    /// Presents the pairing flow itself, preassigned to this component.
    init(component: Component, candidate: PlugCandidate) {
        self.component = component
        self.candidate = candidate
        self.onPair = nil
    }

    private var savings: Measured? { candidate.estimatedSavings ?? estimate }

    var body: some View {
        if model.flags.plugFeaturesEnabled {
            card
                .task(id: candidate) { await loadEstimate() }
                .sheet(isPresented: $showsPairing) {
                    PairingFlow(preselectedComponentID: component.id)
                }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(component.name, systemImage: "powerplug.fill")
                .font(.headline)
            Group {
                if let savings {
                    Text("Charging this only when the grid is clean would save ~\(savings.formatted)/yr.")
                } else {
                    Text("Needs ~\(Measured.format(candidate.requiredHoursPerDay)) h of charging a day, which can shift to clean-grid hours.")
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let savings { TierBadge(tier: savings.tier) }
                Spacer()
                Button {
                    if let onPair { onPair() } else { showsPairing = true }
                } label: {
                    Label("Pair a Shelly plug", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .glassCard(tint: Theme.leaf.opacity(0.15))
    }

    private func loadEstimate() async {
        guard candidate.estimatedSavings == nil else { return }
        let services = model.services
        guard let outlook = try? await GridOutlook.load(grid: services.grid, reference: services.reference,
                                                        profile: model.profile) else { return }
        estimate = PlugSavingsEstimate.yearly(for: candidate, outlook: outlook)
    }
}

#Preview {
    PlugRecommendationCard(component: Component(name: "E-bike charger", category: .electronic),
                           candidate: PlugCandidate(loadType: .eBike, chargerWatts: 170, dailyKWh: 0.25))
        .padding()
        .environment(AppModel.preview())
}
