import SwiftUI
import GreenCore

/// "You're greener than X% of people like you" for the selected metric.
struct PercentileHeroCard: View {
    let metric: MetricKey
    let greenerThan: Double
    let userValue: Double
    let peerMedian: Double

    private var percent: String { SharePercent.format(greenerThan) }

    var body: some View {
        GlassCard(tint: Theme.leaf.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 10) {
                Label(CohortMetric.shortName(metric), systemImage: metric.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(percent)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.leaf)
                        .contentTransition(.numericText(value: greenerThan))
                    Text("greener")
                        .font(.title3.weight(.semibold))
                }
                Text("You're greener than \(percent) of people like you.")
                    .font(.headline)
                HStack(spacing: 16) {
                    stat("You", value: userValue)
                    stat("Peer median", value: peerMedian)
                }
                .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(YearlyValue.format(value, metric: metric))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

/// Formats a yearly cohort value (canonical metric units) for display, e.g. "2.6k lb CO₂e/yr".
enum YearlyValue {
    static func format(_ value: Double, metric: MetricKey) -> String {
        let symbol = DisplayUnits.symbol(metric.unit)
        let perYear = metric == .yearlyElectricity ? "" : "/yr"
        return "\(Measured.format(DisplayUnits.value(value, metric.unit))) \(symbol)\(perYear)"
    }
}

#Preview {
    PercentileHeroCard(metric: .carbon, greenerThan: 0.68, userValue: 420, peerMedian: 610)
        .padding()
}
