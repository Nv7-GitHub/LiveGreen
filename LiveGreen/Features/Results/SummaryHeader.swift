import SwiftUI
import GreenCore

/// Scan summary (spec §6): the selected metric's total (or every additive total for "All") and the
/// confidence meter.
struct SummaryHeader: View {
    let result: ScanResult
    let filter: ResultMetricFilter

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(result.components.count) items")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(result.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            VStack(alignment: .leading, spacing: 12) {
                if let perYear = yearly(metric, in: yearlyTotals) {
                    totalBlock("\(metric.displayName) per year", perYear, prominent: true)
                    Divider()
                    totalBlock("Lifetime / as pictured", total, prominent: false)
                } else {
                    totalBlock("Total \(metric.displayName.lowercased())", total, prominent: true)
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

    private func totalBlock(_ title: String, _ measured: Measured, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(measured.formatted)
                    .font(prominent ? .largeTitle.weight(.bold).monospacedDigit() : .title3.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                TierBadge(tier: measured.tier)
            }
            Text("Range \(measured.formattedRange)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var allTotals: some View {
        let perYear = yearlyTotals
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(ScanTotals.additiveMetrics, id: \.self) { metric in
                if let total = result.totals[metric] {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(metric.displayName, systemImage: metric.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let yearly = yearly(metric, in: perYear) {
                            HStack(spacing: 4) {
                                Text("\(yearly.formatted)/yr").font(.subheadline.weight(.semibold).monospacedDigit())
                                TierBadge(tier: yearly.tier)
                            }
                            Text("\(total.formatted) as pictured")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Text(total.formatted).font(.subheadline.weight(.semibold).monospacedDigit())
                                TierBadge(tier: total.tier)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
