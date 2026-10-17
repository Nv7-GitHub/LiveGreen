import SwiftUI
import Charts
import GreenCore

/// Sparkline of the "greener than" percentile after each saved scan (spec §9).
struct PercentileTrendCard: View {
    let points: [CompareAnalysis.TrendPoint]

    private var change: Int? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        return Int(((last.greenerThan - first.greenerThan) * 100).rounded())
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Percentile over time").font(.headline)
                    Spacer()
                    if let change {
                        Label("\(change >= 0 ? "+" : "")\(change) pts",
                              systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(change >= 0 ? Theme.leaf : Theme.warning)
                    }
                }
                if points.count > 1 {
                    Chart(points) { point in
                        AreaMark(x: .value("Scan", point.index), y: .value("Greener than", point.greenerThan * 100))
                            .foregroundStyle(Theme.leaf.opacity(0.18).gradient)
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Scan", point.index), y: .value("Greener than", point.greenerThan * 100))
                            .foregroundStyle(Theme.leaf)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        if point.id == points.last?.id {
                            PointMark(x: .value("Scan", point.index), y: .value("Greener than", point.greenerThan * 100))
                                .foregroundStyle(Theme.leaf)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel { if let y = value.as(Int.self) { Text("\(y)%") } }
                        }
                    }
                    .frame(height: 90)
                    .accessibilityLabel("Percentile trend across \(points.count) scans")
                } else {
                    Text("Save another scan to see your trend.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
