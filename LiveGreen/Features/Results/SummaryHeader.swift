import SwiftUI
import GreenCore

/// Scan summary (spec §6): the selected metric's yearly total as one big number with its likely range,
/// lifetime and item count as secondary stats, and where the numbers come from. "All" shows every
/// additive total as compact tiles.
struct SummaryHeader: View {
    let result: ScanResult
    let filter: ResultMetricFilter

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                if let metric = filter.metric {
                    singleTotal(metric)
                } else {
                    allTotals
                }
                ConfidenceMeter(components: result.components)
            }
        }
    }

    /// Yearly totals saved with the scan; older scans compute them on the fly.
    private var yearlyTotals: [MetricKey: Measured] {
        result.yearlyTotals.isEmpty ? ImpactEngine().yearlyTotals(result.components, seed: result.totalsSeed)
                                    : result.yearlyTotals
    }

    /// Spec §5.6: totals are shown per year and as pictured (one serving or unit of consumables, the whole
    /// life of durables). Yearly electricity is already per year.
    private func yearly(_ metric: MetricKey, in totals: [MetricKey: Measured]) -> Measured? {
        metric == .yearlyElectricity ? nil : totals[metric]
    }

    @ViewBuilder private func singleTotal(_ metric: MetricKey) -> some View {
        if let total = result.totals[metric] {
            let perYear = yearly(metric, in: yearlyTotals)
            let headline = perYear ?? total
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(perYear == nil ? metric.displayName : "\(metric.displayName) per year",
                          systemImage: metric.systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Measured.format(headline.value))
                            .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text(headline.unit.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("Likely \(headline.formattedRange)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if perYear != nil { stat("Lifetime", Measured.format(total.value), unit: total.unit.symbol) }
                    stat("Items", "\(result.components.count)", unit: nil)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("summaryTotal")
        } else {
            Label("No \(metric.displayName.lowercased()) figures for these items", systemImage: metric.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.headline.monospacedDigit()).contentTransition(.numericText())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))
    }

    private var allTotals: some View {
        let perYear = yearlyTotals
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                         alignment: .leading, spacing: 10) {
            ForEach(ScanTotals.additiveMetrics, id: \.self) { metric in
                if let total = result.totals[metric] {
                    let shown = yearly(metric, in: perYear) ?? total
                    VStack(alignment: .leading, spacing: 4) {
                        Label(metric.displayName, systemImage: metric.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Measured.format(shown.value)).font(.title3.weight(.bold).monospacedDigit())
                            Text(shown.unit.symbol).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(yearly(metric, in: perYear) == nil ? "total" : "per year")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
