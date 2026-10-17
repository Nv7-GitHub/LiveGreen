import SwiftUI
import Charts
import GreenCore

/// Current vs. alternative bars per key metric, with range whiskers and a "% better" chip (spec §7). Values are on
/// the GreenScore comparison basis: per year where the impact recurs (carbon, electricity, and everything for
/// consumables), else for the item as made. Metrics a swap leaves unchanged are left out.
struct ComparisonChart: View {
    let component: Component
    let alternative: Alternative
    /// Yearly charging carbon, used instead of per-metric bars for the smart-plug option.
    var charging: SmartPlugAlternative.ChargingCarbon?

    var body: some View {
        if alternative.kind == .smartPlugScheduling {
            plugComparison
        } else {
            metricComparisons
        }
    }

    @ViewBuilder private var plugComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let charging {
                MetricComparison(metric: .carbon, title: "Charging carbon per year", systemImage: "bolt.badge.clock",
                                 current: charging.current, alternative: charging.scheduled, perYear: true)
            } else if let savings = component.plugCandidate?.estimatedSavings {
                Label("Saves about \(savings.formatted) a year", systemImage: "bolt.badge.clock")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Same device, so every other metric stays the same.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var metricComparisons: some View {
        let metrics = SwapMath.keyMetrics(component, alternative)
        return VStack(alignment: .leading, spacing: 16) {
            if metrics.isEmpty {
                Text("No shared metrics to compare yet.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(metrics, id: \.self) { metric in
                if let values = SwapMath.comparison(metric, component, alternative) {
                    MetricComparison(metric: metric,
                                     title: values.annualized ? "\(metric.displayName) per year" : metric.displayName,
                                     systemImage: metric.systemImage, current: values.current,
                                     alternative: values.swap, perYear: values.annualized)
                }
            }
        }
    }
}

/// One metric's bar pair.
private struct MetricComparison: View {
    let metric: MetricKey
    let title: String
    let systemImage: String
    let current: Measured
    let alternative: Measured
    /// The values are yearly amounts, so the labels say "/yr".
    var perYear = false

    private struct Bar: Identifiable {
        let id: String
        let measured: Measured
    }

    private var bars: [Bar] {
        [Bar(id: "Current", measured: current), Bar(id: "Swap", measured: alternative)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
                Spacer()
                if let percent = SwapMath.percentBetter(metric, current: current, alternative: alternative) {
                    // "0% better" says nothing; the bars still show the values.
                    if Int(percent.rounded()) != 0 { BetterChip(percent: percent) }
                } else if alternative.value > current.value {
                    // Up from zero: no percentage, so the chip only says which way it went.
                    BetterChip(percent: metric.higherIsBetter ? .infinity : -.infinity)
                }
            }
            Text("\(current.formatted)\(suffix) → \(alternative.formatted)\(suffix)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Chart(bars) { bar in
                BarMark(x: .value(title, bar.measured.value), y: .value("Option", bar.id), height: 18)
                    .foregroundStyle(by: .value("Option", bar.id))
                    .cornerRadius(6)
                RuleMark(xStart: .value("Low", bar.measured.low), xEnd: .value("High", bar.measured.high),
                         y: .value("Option", bar.id))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(Color.primary.opacity(0.7))
                ForEach(0..<2, id: \.self) { end in
                    PointMark(x: .value("Bound", end == 0 ? bar.measured.low : bar.measured.high),
                              y: .value("Option", bar.id))
                        .symbol { Capsule().fill(Color.primary.opacity(0.7)).frame(width: 1.5, height: 10) }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) { Text(Measured.format(DisplayUnits.value(number, current.unit))) }
                    }
                }
            }
            // A color legend names the bars; inline y-axis labels would sit on top of them.
            .chartForegroundStyleScale(["Current": Color.gray.opacity(0.55), "Swap": Theme.leaf])
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxisLabel(current.displaySymbol + suffix, alignment: .trailing)
            .frame(height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): current \(current.formatted)\(suffix), swap \(alternative.formatted)\(suffix)")
        }
    }

    /// kWh/yr already says per year.
    private var suffix: String { perYear && current.unit != .kilowattHoursPerYear ? "/yr" : "" }
}

/// Glass capsule with the relative improvement; an infinite percent (a rise from zero) reads "Worse".
struct BetterChip: View {
    let percent: Double

    var body: some View {
        let better = percent >= 0
        Text(!percent.isFinite ? (better ? "Better" : "Worse")
             : better ? "\(Int(percent.rounded()))% better" : "\(Int((-percent).rounded()))% worse")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(better ? Theme.leaf : Theme.warning)
            .glassEffect(.regular.tint((better ? Theme.leaf : Theme.warning).opacity(0.25)), in: .capsule)
    }
}

#Preview {
    let component = AlternativesPreviewData.result.components[0]
    ScrollView {
        VStack(spacing: 24) {
            ComparisonChart(component: component, alternative: component.alternatives[0])
            if let plug = component.alternatives.first(where: { $0.kind == .smartPlugScheduling }) {
                ComparisonChart(component: component, alternative: plug, charging: AlternativesPreviewData.charging)
            }
        }
        .padding()
    }
}
