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
                Text(scan.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let carbon = scan.totals[.carbon] {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(carbon.formatted)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    TierBadge(tier: carbon.tier)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var itemSummary: String {
        let names = scan.components.map(\.name)
        guard !names.isEmpty else { return "No items" }
        let shown = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }
}
