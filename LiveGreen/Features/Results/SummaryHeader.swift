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

    @ViewBuilder private func singleTotal(_ metric: MetricKey) -> some View {
        if let total = result.totals[metric] {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total \(metric.displayName.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(total.formatted)
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    TierBadge(tier: total.tier)
                }
                Text("Range \(total.formattedRange)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("summaryTotal")
        } else {
            Label("No \(metric.displayName.lowercased()) figures for these items", systemImage: metric.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var allTotals: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(ScanTotals.additiveMetrics, id: \.self) { metric in
                if let total = result.totals[metric] {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(metric.displayName, systemImage: metric.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(total.formatted).font(.subheadline.weight(.semibold).monospacedDigit())
                            TierBadge(tier: total.tier)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
