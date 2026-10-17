import SwiftUI
import GreenCore

/// Inspector row for one metric (spec §6): value, range bar, tier badge and a Sources disclosure with
/// tappable citations.
struct MeasuredRow: View {
    let metric: MetricKey
    let measured: Measured?

    @State private var showsSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(metric.displayName, systemImage: metric.systemImage)
                    .font(.subheadline)
                Spacer()
                if let measured {
                    Text(measured.formatted)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    TierBadge(tier: measured.tier)
                } else {
                    Text("Not resolved").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let measured {
                RangeBar(measured: measured)
                HStack {
                    Text(measured.formattedRange)
                    Spacer()
                    Text(measured.tier.displayName)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                DisclosureGroup(isExpanded: $showsSources) {
                    SourcesList(sources: measured.sources, tier: measured.tier)
                        .padding(.top, 4)
                } label: {
                    Text(measured.sources.isEmpty ? "Sources" : "Sources (\(measured.sources.count))")
                        .font(.caption.weight(.medium))
                }
                .tint(Theme.leaf)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("measuredRow.\(metric.rawValue)")
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
