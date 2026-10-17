import SwiftUI
import GreenCore

/// Where the scan's carbon figures come from (spec §6): a bar segmented by evidence tier with a
/// plain-language verdict. The confidence value is the share resolved from exact records or cited specs.
struct ConfidenceMeter: View {
    let components: [Component]

    var body: some View {
        let byTier = ResultInsights.carbonShareByTier(components)
        let confidence = ResultInsights.confidence(components)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: confidence >= 0.5 ? "checkmark.seal.fill" : "info.circle")
                    .foregroundStyle(confidence >= 0.5 ? Theme.leaf : .secondary)
                Text(Self.verdict(confidence))
                    .font(.footnote.weight(.semibold))
                Spacer()
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(byTier, id: \.tier) { part in
                        Capsule()
                            .fill(part.tier.color.gradient)
                            .frame(width: max(4, (geometry.size.width - CGFloat(byTier.count - 1) * 2) * part.share))
                    }
                }
            }
            .frame(height: 6)
            .background(.fill.tertiary, in: .capsule)
            HStack(spacing: 12) {
                ForEach(byTier, id: \.tier) { part in
                    HStack(spacing: 4) {
                        Circle().fill(part.tier.color).frame(width: 7, height: 7)
                        Text("\(Self.sourceName(part.tier)) \(part.share, format: .percent.precision(.fractionLength(0)))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.verdict(confidence)). \(Int((confidence * 100).rounded())) percent of carbon from records or cited specs")
        .accessibilityIdentifier("confidenceMeter")
    }

    static func verdict(_ confidence: Double) -> String {
        switch confidence {
        case 0.66...: "Mostly from product records"
        case 0.33...: "Partly from product records"
        case 0.01...: "Mostly typical values for similar items"
        default: "Estimated from typical values for similar items"
        }
    }

    static func sourceName(_ tier: Tier) -> String {
        switch tier {
        case .exactRecord: "Records"
        case .researchedSpec: "Spec sheets"
        case .factorModel: "Typical values"
        case .estimate: "AI estimates"
        }
    }
}
