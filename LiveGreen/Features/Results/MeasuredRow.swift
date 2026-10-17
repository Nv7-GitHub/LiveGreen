import SwiftUI
import GreenCore

/// Inspector row for one metric (spec §6): value, range bar, tier badge, an optional breakdown (item vs
/// packaging plastic, carbon per year vs lifetime) and a Sources disclosure with tappable citations.
/// Only metrics with a value get a row; missing ones are left off rather than shown as gaps.
struct MeasuredRow: View {
    let metric: MetricKey
    let measured: Measured
    var breakdown: [MeasuredBreakdown] = []

    @State private var showsSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(metric.displayName, systemImage: metric.systemImage)
                    .font(.subheadline)
                Spacer()
                Text(measured.formatted)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                TierBadge(tier: measured.tier)
            }
            RangeBar(measured: measured)
            HStack {
                Text(measured.formattedRange)
                Spacer()
                Text(measured.tier.displayName)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            if !breakdown.isEmpty { breakdownRow }
            DisclosureGroup(isExpanded: $showsSources) {
                SourcesList(sources: measured.sources, tier: measured.tier)
                    .padding(.top, 4)
            } label: {
                Text(measured.sources.isEmpty ? "Sources" : "Sources (\(measured.sources.count))")
                    .font(.caption.weight(.medium))
            }
            .tint(Theme.leaf)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("measuredRow.\(metric.rawValue)")
    }

    private var breakdownRow: some View {
        HStack(spacing: 12) {
            ForEach(breakdown) { part in
                VStack(alignment: .leading, spacing: 1) {
                    Text(part.label).font(.caption2).foregroundStyle(.secondary)
                    Text(part.measured.formatted).font(.caption.weight(.medium).monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

/// Citations behind one value; linked titles open in the browser.
private struct SourcesList: View {
    let sources: [Source]
    let tier: Tier

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sources.isEmpty {
                Text(tier == .estimate ? "Model estimate with a deliberately wide range; no citation."
                                       : "Derived in the app from other values on this item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TierBadge(tier: source.tier)
                        if let url = source.url {
                            Link(destination: url) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(source.title).multilineTextAlignment(.leading)
                                    Image(systemName: "arrow.up.right.square").imageScale(.small)
                                }
                            }
                            .font(.caption)
                        } else {
                            Text(source.title).font(.caption)
                        }
                    }
                    if let quote = source.quote, !quote.isEmpty {
                        Text("“\(quote)”")
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                    if let host = source.url?.host() {
                        Text(host).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
