import SwiftUI
import GreenCore

/// Sums the savings of every chosen swap (spec §7): carbon and electricity per year, and water or plastic
/// per year only for things bought again and again; for durable items those are saved once, when made.
struct ProjectedSavingsCard: View {
    let savings: [MetricKey: SwapMath.SavingSplit]
    let swapCount: Int

    var body: some View {
        GlassCard(tint: Theme.leaf.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Projected savings", systemImage: "chart.line.downtrend.xyaxis")
                    .font(.headline)
                if swapCount == 0 {
                    Text("Pick a swap above to see what it saves.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(SwapMath.savingsMetrics.filter { savings[$0] != nil }, id: \.self) { metric in
                        if let split = savings[metric] { row(metric, split) }
                    }
                    Text("From \(swapCount) swap\(swapCount == 1 ? "" : "s"), using your usage answers. \"Once\" is the saving from making the item; ranges carry each value's uncertainty.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ metric: MetricKey, _ split: SwapMath.SavingSplit) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(metric.displayName, systemImage: metric.systemImage)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let yearly = split.yearly { amount(yearly, metric, suffix: yearlySuffix(metric)) }
                if let once = split.oneTime { amount(once, metric, suffix: " once") }
            }
        }
        .font(.subheadline)
    }

    private func amount(_ saving: EstimateRange, _ metric: MetricKey, suffix: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(Self.signed(-saving.value, metric)) \(DisplayUnits.symbol(metric.unit))\(suffix)")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(saving.value >= 0 ? Theme.leaf : Theme.warning)
            // The headline is the change (negative = saved), so the range uses the same sign.
            Text("\(Self.signed(-saving.high, metric)) to \(Self.signed(-saving.low, metric))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private static func signed(_ change: Double, _ metric: MetricKey) -> String {
        let magnitude = Measured.format(DisplayUnits.value(abs(change), metric.unit))
        if change > 0 { return "+\(magnitude)" }
        return change < 0 ? "−\(magnitude)" : magnitude
    }

    /// kWh/yr already says "per year".
    private func yearlySuffix(_ metric: MetricKey) -> String {
        metric.unit == .kilowattHoursPerYear ? "" : "/yr"
    }
}

#Preview {
    ProjectedSavingsCard(savings: [.carbon: .init(yearly: EstimateRange(value: 42, low: 20, high: 70)),
                                   .water: .init(yearly: EstimateRange(value: 120, low: 40, high: 200),
                                                 oneTime: EstimateRange(value: 800, low: 300, high: 1_200))],
                         swapCount: 2)
        .padding()
}
