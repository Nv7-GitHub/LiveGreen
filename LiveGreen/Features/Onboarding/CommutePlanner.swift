import SwiftUI
import GreenCore

/// Pick every way you get around, then set the weekly distance for each. Each mode shows its own yearly
/// carbon so the trade-offs are visible while answering.
struct CommutePlanner: View {
    @Binding var distances: [CommuteMode: Double]

    /// Starting distance for a newly picked mode, km per week.
    private static let defaultKm = 40.0

    private var selection: Binding<Set<CommuteMode>> {
        Binding(get: { Set(distances.keys) }, set: { newValue in
            let added = newValue.subtracting(distances.keys)
            // Working from home replaces commuting; picking a commute mode clears it.
            if added.contains(.remote) {
                distances = [.remote: 0]
                return
            }
            var updated = distances.filter { newValue.contains($0.key) && $0.key != .remote }
            for mode in added { updated[mode] = Self.defaultKm }
            distances = updated
        })
    }

    private var movingModes: [CommuteMode] {
        CommuteMode.allCases.filter { distances[$0] != nil && $0 != .remote }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select all that apply").font(.footnote).foregroundStyle(.secondary)
            MultiChoiceChips(selection: selection)
            ForEach(movingModes, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 4) {
                    DistanceSlider(title: mode.profileLabel, kmPerWeek: Binding(
                        get: { distances[mode] ?? 0 }, set: { distances[mode] = $0 }))
                    Text(yearlyLine(mode))
                        .font(.caption)
                        .foregroundStyle((LifestyleEstimate.kgPerKm[mode] ?? 0) > 0.05 ? Theme.warning : Theme.leaf)
                        .contentTransition(.numericText())
                }
                .padding(12)
                .background(.fill.quaternary, in: .rect(cornerRadius: 14))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if distances.isEmpty {
                Text("Pick at least one, or Work from home.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: movingModes)
    }

    private func yearlyLine(_ mode: CommuteMode) -> String {
        let kg = (LifestyleEstimate.kgPerKm[mode] ?? 0) * (distances[mode] ?? 0) * 52
        guard kg > 0 else { return "≈ 0 carbon from \(mode.profileLabel.lowercased())" }
        return "≈ \(DisplayUnits.carbon(kg: kg)) a year"
    }
}
