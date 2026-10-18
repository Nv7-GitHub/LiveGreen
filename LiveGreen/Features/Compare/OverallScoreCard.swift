import SwiftUI
import GreenCore

/// Your overall GreenScore (`CohortModel.greenScore`): the score out of 100, where you rank among friends, how your
/// footprint compares with a typical person's on each metric, and what smart-plug scheduling takes off carbon.
struct OverallScoreCard: View {
    let score: PersonalGreenScore
    let rank: Int
    let boardSize: Int
    /// Yearly kg CO2e the paired plugs' schedules avoid; counted in carbon.
    let plugSavingsKg: Double
    /// Whether to suggest plug scheduling when nothing is scheduled.
    let suggestsPlug: Bool

    var body: some View {
        GlassCard(tint: Theme.leaf.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Overall GreenScore", systemImage: "trophy")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(score.points)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.leaf)
                        .contentTransition(.numericText(value: Double(score.points)))
                    Text("/ 100")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(rankLine)
                    .font(.headline)
                Text("\(OverallWording.versusTypical(score.footprintRatio)), on average across carbon, electricity, water and land. 50 is a typical person in your region.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(CohortMetric.all, id: \.self) { metric in
                        if let ratio = score.ratio(for: metric) { metricRow(metric, ratio: ratio) }
                    }
                }
                .padding(.top, 4)
                plugLine
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("overallScore")
    }

    private var rankLine: String {
        rank == 1 ? "Greenest of your \(boardSize - 1) friends" : "#\(rank) of \(boardSize) among your friends"
    }

    private func metricRow(_ metric: MetricKey, ratio: Double) -> some View {
        HStack {
            Label(CohortMetric.shortName(metric), systemImage: metric.systemImage)
            Spacer()
            Text(OverallWording.shortVersusTypical(ratio))
                .monospacedDigit()
                .foregroundStyle(OverallWording.isAboutTypical(ratio) ? .secondary : ratio < 1 ? Theme.leaf : Theme.warning)
        }
        .font(.subheadline)
    }

    @ViewBuilder private var plugLine: some View {
        if plugSavingsKg > 0 {
            Label("Smart-plug green hours take \(DisplayUnits.carbon(kg: plugSavingsKg)) a year off your carbon.",
                  systemImage: "powerplug.fill")
                .font(.caption)
                .foregroundStyle(Theme.leaf)
                .fixedSize(horizontal: false, vertical: true)
        } else if suggestsPlug {
            Label("Scheduling a smart plug for green hours lowers your carbon here too.", systemImage: "powerplug")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Words for a footprint against a typical person's, as a ratio (0.8 = 20% smaller).
nonisolated enum OverallWording {
    /// Within 2.5% reads as typical.
    static func isAboutTypical(_ ratio: Double) -> Bool { abs(ratio - 1) < 0.025 }

    private static func percent(_ ratio: Double) -> String {
        "\(Int((abs(ratio - 1) * 100).rounded()))%"
    }

    /// "18% smaller footprint than typical", "About a typical footprint".
    static func versusTypical(_ ratio: Double) -> String {
        if isAboutTypical(ratio) { return "About a typical footprint" }
        return "\(percent(ratio)) \(ratio < 1 ? "smaller" : "bigger") footprint than typical"
    }

    /// "18% less than typical", "12% more than typical", "Typical".
    static func shortVersusTypical(_ ratio: Double) -> String {
        if isAboutTypical(ratio) { return "Typical" }
        return "\(percent(ratio)) \(ratio < 1 ? "less" : "more") than typical"
    }
}

#Preview {
    OverallScoreCard(score: PersonalGreenScore(score: 0.2, changes: [.carbon: 0.4, .yearlyElectricity: -0.1,
                                                                     .water: 0.3, .land: 0.2]),
                     rank: 3, boardSize: 10, plugSavingsKg: 18, suggestsPlug: true)
        .padding()
}
