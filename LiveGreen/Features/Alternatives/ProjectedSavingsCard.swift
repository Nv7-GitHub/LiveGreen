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
                    ForEach(SwapMath.savingsMetrics.filter { shows(savings[$0]) }, id: \.self) { metric in
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
                if let yearly = split.yearly, Self.isChange(yearly) { amount(yearly, metric, suffix: yearlySuffix(metric)) }
                if let once = split.oneTime, Self.isChange(once) { amount(once, metric, suffix: " once") }
            }
        }
        .font(.subheadline)
    }

    private func amount(_ saving: EstimateRange, _ metric: MetricKey, suffix: String) -> some View {
        // One unit for the figure and its range, suited to its size (lb rather than 3,527 oz of car plastic).
        let scale = DisplayUnits.scale(for: metric.unit, magnitude: saving.value)
        return VStack(alignment: .trailing, spacing: 2) {
            Text("\(Self.signed(-saving.value, scale))\(DisplayUnits.nbsp)\(scale.symbol)\(suffix)")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(saving.value >= 0 ? Theme.leaf : Theme.warning)
            // The headline is the change (negative = saved), so the range uses the same sign.
            Text("\(Self.signed(-saving.high, scale)) to \(Self.signed(-saving.low, scale))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    /// A total that nets out to nothing gets no line; a net loss still does.
    private static func isChange(_ saving: EstimateRange) -> Bool {
        SwapMath.isNetChange(saving, baseline: 0)
    }

    private func shows(_ split: SwapMath.SavingSplit?) -> Bool {
        [split?.yearly, split?.oneTime].contains { $0.map(Self.isChange) ?? false }
    }

    private static func signed(_ change: Double, _ scale: DisplayScale) -> String {
        let magnitude = Measured.format(abs(change) * scale.factor, resolution: scale.resolution)
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
