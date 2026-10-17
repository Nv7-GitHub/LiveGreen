import SwiftUI
import GreenCore

/// Sums the yearly deltas of every chosen swap (spec §7).
struct ProjectedSavingsCard: View {
    let savings: [MetricKey: EstimateRange]
    let swapCount: Int

    var body: some View {
        GlassCard(tint: Theme.leaf.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Projected yearly savings", systemImage: "chart.line.downtrend.xyaxis")
                    .font(.headline)
                if swapCount == 0 {
                    Text("Pick a swap above to see what it saves each year.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(SwapMath.savingsMetrics.filter { savings[$0] != nil }, id: \.self) { metric in
                        if let saving = savings[metric] { row(metric, saving) }
                    }
                    Text("From \(swapCount) swap\(swapCount == 1 ? "" : "s"), using your usage answers. Ranges carry each value's uncertainty.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ metric: MetricKey, _ saving: EstimateRange) -> some View {
        let saves = saving.value >= 0
        return HStack(alignment: .firstTextBaseline) {
            Label(metric.displayName, systemImage: metric.systemImage)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Self.signed(-saving.value)) \(yearlyUnit(metric))")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(saves ? Theme.leaf : Theme.warning)
                // The headline is the yearly change (negative = saved), so the range uses the same sign.
                Text("\(Self.signed(-saving.high)) to \(Self.signed(-saving.low))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private static func signed(_ change: Double) -> String {
        let magnitude = Measured.format(abs(change))
        if change > 0 { return "+\(magnitude)" }
        return change < 0 ? "−\(magnitude)" : magnitude
    }

    private func yearlyUnit(_ metric: MetricKey) -> String {
        metric.unit == .kilowattHoursPerYear ? metric.unit.symbol : "\(metric.unit.symbol)/yr"
    }
}

#Preview {
    ProjectedSavingsCard(savings: [.carbon: EstimateRange(value: 42, low: 20, high: 70),
                                   .yearlyElectricity: EstimateRange(value: 18, low: 5, high: 30)],
                         swapCount: 2)
        .padding()
}
