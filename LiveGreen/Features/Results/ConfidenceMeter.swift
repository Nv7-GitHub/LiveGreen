import SwiftUI
import GreenCore

/// Share of the scan's carbon resolved from exact records or cited specs (T1/T2), drawn as a bar
/// segmented by tier (spec §6).
struct ConfidenceMeter: View {
    let components: [Component]

    var body: some View {
        let byTier = ResultInsights.carbonShareByTier(components)
        let confidence = ResultInsights.confidence(components)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Confidence", systemImage: "checkmark.seal")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(confidence, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(byTier, id: \.tier) { part in
                        Rectangle()
                            .fill(part.tier.color.gradient)
                            .frame(width: max(2, (geometry.size.width - CGFloat(byTier.count - 1) * 2) * part.share))
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 8)
            .background(.quaternary, in: .capsule)
            HStack(spacing: 10) {
                ForEach(byTier, id: \.tier) { part in
                    HStack(spacing: 4) {
                        TierBadge(tier: part.tier)
                        Text(part.share, format: .percent.precision(.fractionLength(0)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("of carbon comes from exact records or cited spec sheets.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence \(Int((confidence * 100).rounded())) percent of carbon from records or cited specs")
        .accessibilityIdentifier("confidenceMeter")
    }
}
