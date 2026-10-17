import SwiftUI
import GreenCore

/// "Charging this only when the grid is clean would save ~X kg CO₂e/yr" card (spec §8.1).
struct PlugRecommendationCard: View {
    let component: Component
    let candidate: PlugCandidate
    let onPair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(component.name, systemImage: "powerplug").font(.headline)
            if let savings = candidate.estimatedSavings {
                Text("Charging this only when the grid is clean would save ~\(savings.formatted)/yr.")
            } else {
                Text("Needs ~\(Measured.format(candidate.requiredHoursPerDay)) h of charging a day, which can shift to clean-grid hours.")
            }
            Button("Pair a Shelly plug", systemImage: "chevron.right", action: onPair)
                .buttonStyle(.glass)
        }
        .font(.subheadline)
    }
}

#Preview {
    PlugRecommendationCard(component: Component(name: "E-bike charger", category: .electronic),
                           candidate: PlugCandidate(loadType: .eBike, chargerWatts: 170, dailyKWh: 0.25)) {}
        .padding()
}
