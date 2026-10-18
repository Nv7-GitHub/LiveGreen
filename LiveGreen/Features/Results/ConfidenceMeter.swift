import SwiftUI
import GreenCore

/// Where the selected metric's figures come from (spec §6): a bar segmented by evidence tier, each item weighted by
/// its yearly value like the headline, with a plain-language verdict. The confidence value is the share resolved
/// from exact records or cited specs; without any, the verdict says how rough the estimate is instead of letting
/// "Typical values 100%" read as certainty.
struct ConfidenceMeter: View {
    let components: [Component]
    var metric: MetricKey = .carbon
    let breakdown: ScanBreakdown

    var body: some View {
        let byTier = breakdown.tierShares(metric, in: components)
        let confidence = breakdown.confidence(metric, in: components)
        let verdict = Self.verdict(confidence: confidence,
                                   photoGuessed: breakdown.photoGuessedShare(metric, in: components),
                                   hasFigures: !byTier.isEmpty)
        VStack(alignment: .leading, spacing: 8) {
            if let verdict {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: confidence >= 0.5 ? "checkmark.seal.fill" : "info.circle")
                        .foregroundStyle(confidence >= 0.5 ? Theme.leaf : .secondary)
                    Text(verdict)
                        .font(.footnote.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
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
        .accessibilityLabel(accessibilitySummary(confidence, verdict: verdict))
        .accessibilityIdentifier("confidenceMeter")
    }

    /// Headline for the share from records or cited specs. Without any, a rough-estimate note when most of the
    /// total rests on the item types and sizes the AI read from the photo; nil when nothing has a figure.
    static func verdict(confidence: Double, photoGuessed: Double, hasFigures: Bool) -> String? {
        switch confidence {
        case 0.66...: return "Mostly from product records"
        case 0.33...: return "Partly from product records"
        case 0.01...: return "Some figures from product records"
        default:
            guard hasFigures else { return nil }
            return photoGuessed >= 0.5 ? "Rough estimate: item types and sizes are guessed from the photo"
                                       : "Estimated from typical values"
        }
    }

    private func accessibilitySummary(_ confidence: Double, verdict: String?) -> String {
        let share = "\(Int((confidence * 100).rounded())) percent of \(metric.displayName.lowercased()) "
            + "from records or cited specs"
        return verdict.map { "\($0). \(share)" } ?? share
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
