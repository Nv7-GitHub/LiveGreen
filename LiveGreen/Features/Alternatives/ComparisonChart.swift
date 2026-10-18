import SwiftUI
import Charts
import GreenCore

/// Current vs. alternative bars per key metric, with range whiskers and a "% better" chip (spec §7), then one line
/// for each other metric the swap changes, so every change the card counts is on screen. Values are on the
/// GreenScore comparison basis: per year where the impact recurs (carbon, electricity, and everything for
/// consumables), else for the item as made. A food swap for a barcoded pack is put on that pack's size and packs a
/// week (`Alternative.onBasis`), so both bars are the same amount of food. Metrics a swap leaves unchanged are left out.
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
        let metrics = SwapMath.shownMetrics(component, alternative)
        return VStack(alignment: .leading, spacing: 16) {
            if metrics.isEmpty {
                Text("No shared metrics to compare yet.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(metrics.prefix(SwapMath.chartLimit), id: \.self) { metric in
                if let values = SwapMath.comparison(metric, component, alternative) {
                    MetricComparison(metric: metric, title: title(metric, annualized: values.annualized),
                                     systemImage: metric.systemImage, current: values.current,
                                     alternative: values.swap, perYear: values.annualized)
                }
            }
            if metrics.count > SwapMath.chartLimit {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(metrics.dropFirst(SwapMath.chartLimit), id: \.self) { metric in
                        if let values = SwapMath.comparison(metric, component, alternative) {
                            MetricChangeLine(metric: metric, title: title(metric, annualized: values.annualized),
                                             current: values.current, alternative: values.swap,
                                             perYear: values.annualized)
                        }
                    }
                }
            }
        }
    }

    private func title(_ metric: MetricKey, annualized: Bool) -> String {
        annualized ? "\(metric.displayName) per year" : metric.displayName
    }
}

/// One metric's change without a chart: name, the two values and the chip.
private struct MetricChangeLine: View {
    let metric: MetricKey
    let title: String
    let current: Measured
    let alternative: Measured
    var perYear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: metric.systemImage).font(.caption.weight(.semibold))
                Spacer()
                if let change = SwapMath.change(metric, current: current, alternative: alternative) {
                    BetterChip(change: change)
                }
            }
            Text("\(current.formatted)\(suffix) → \(alternative.formatted)\(suffix)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var suffix: String { perYear && current.unit != .kilowattHoursPerYear ? "/yr" : "" }
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

    /// Round display-unit ticks; the last one ends the axis.
    private var ticks: [Double] {
        SwapMath.axisTicks(upTo: max(current.high, alternative.high, current.value, alternative.value), unit: current.unit)
    }

    var body: some View {
        let ticks = ticks
        let axisEnd = ticks.last ?? 1
        // A bar this short still shows its color, so a value near zero is not just a whisker tick.
        let shortest = axisEnd * 0.015
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
                Spacer()
                if let change = SwapMath.change(metric, current: current, alternative: alternative) {
                    BetterChip(change: change)
                }
            }
            Text("\(current.formatted)\(suffix) → \(alternative.formatted)\(suffix)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Chart(bars) { bar in
                BarMark(x: .value(title, max(bar.measured.value, shortest)), y: .value("Option", bar.id), height: 18)
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
            .chartXScale(domain: 0...axisEnd)
            .chartXAxis {
                AxisMarks(values: ticks) { value in
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

/// Glass capsule with a metric's change as `SwapMath.change` words it ("64% better", "+87 pts", "12× worse").
struct BetterChip: View {
    let change: SwapMath.MetricChange

    var body: some View {
        let better = change.isBetter
        Text(change.label)
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
