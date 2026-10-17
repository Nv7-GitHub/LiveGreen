import SwiftUI
import GreenCore

/// One past scan: thumbnail, title, item count, date and carbon total.
struct HistoryRow: View {
    let scan: ScanResult

    var body: some View {
        HStack(spacing: 14) {
            ScanThumbnail(scan: scan)
            VStack(alignment: .leading, spacing: 3) {
                Text(scan.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(itemSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(scan.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let carbon = yearlyCarbon {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(carbon.formatted)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text("per year").font(.caption2).foregroundStyle(.secondary)
                    TierBadge(tier: carbon.tier)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Per-year carbon, matching the results header's headline figure.
    private var yearlyCarbon: Measured? {
        let yearly = scan.yearlyTotals.isEmpty ? ImpactEngine().yearlyTotals(scan.components, seed: scan.totalsSeed)
                                               : scan.yearlyTotals
        return yearly[.carbon] ?? scan.totals[.carbon]
    }

    private var itemSummary: String {
        let names = scan.components.map(\.name)
        guard !names.isEmpty else { return "No items" }
        let shown = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }
}
