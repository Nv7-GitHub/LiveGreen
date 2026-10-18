import SwiftUI
import Charts
import GreenCore

/// The lognormal peer distribution with the user's position marked (spec §9).
struct CohortDistributionChart: View {
    let metric: MetricKey
    let distribution: LogNormal
    let userValue: Double

    private var markerValue: Double { max(userValue, distribution.median * 1e-3) }

    /// Wide enough to include the user's marker, without flattening the curve.
    private var spread: Double {
        let z = abs(log(markerValue / distribution.median)) / max(distribution.sigma, 0.01)
        return min(max(3, z + 0.5), 6)
    }

    /// Labels sit on the outer side of each rule so "You" and "Median" never overlap.
    private var userBelowMedian: Bool { markerValue < distribution.median }

    private var curve: [LogNormal.CurvePoint] { distribution.curve(points: 90, spread: spread) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where you sit among peers")
                    .font(.headline)
                Chart {
                    ForEach(curve, id: \.x) { point in
                        AreaMark(x: .value("Footprint", point.x), y: .value("Density", point.density),
                                 series: .value("Band", "All peers"))
                            .foregroundStyle(Color.secondary.opacity(0.25))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(curve.filter { $0.x >= markerValue }, id: \.x) { point in
                        AreaMark(x: .value("Footprint", point.x), y: .value("Density", point.density),
                                 series: .value("Band", "Heavier than you"))
                            .foregroundStyle(Theme.leaf.opacity(0.55).gradient)
                            .interpolationMethod(.catmullRom)
                    }
                    RuleMark(x: .value("Median", distribution.median))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: userBelowMedian ? .topTrailing : .topLeading, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("Median").font(.caption2).foregroundStyle(.secondary)
                        }
                    RuleMark(x: .value("You", markerValue))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .annotation(position: userBelowMedian ? .topLeading : .topTrailing, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text("You")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .foregroundStyle(.white)
                                .background(Theme.leaf, in: .capsule)
                        }
                }
                .chartXScale(type: .log)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let x = value.as(Double.self) { Text(Measured.format(DisplayUnits.value(x, metric.unit))) }
                        }
                    }
                }
                .padding(.top, 28)
                .frame(height: 210)
                .accessibilityLabel("Peer distribution of \(CohortMetric.shortName(metric))")
                .accessibilityValue("You: \(YearlyValue.format(userValue, metric: metric)); median \(YearlyValue.format(distribution.median, metric: metric))")

                Text("\(CohortMetric.basis(metric)) per person \(CohortMetric.peers(metric)), \(DisplayUnits.symbol(metric.unit)) · green = people with a larger footprint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    CohortDistributionChart(metric: .carbon, distribution: LogNormal(median: 600, sigma: 0.55), userValue: 420)
        .padding()
}
