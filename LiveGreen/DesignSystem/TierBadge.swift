import SwiftUI
import GreenCore

/// Small capsule showing an evidence tier ("T1"…"T4") in its color.
struct TierBadge: View {
    let tier: Tier

    var body: some View {
        Text(tier.badge)
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(tier.color, in: .capsule)
            .accessibilityLabel(tier.displayName)
    }
}

#Preview {
    HStack { ForEach(Tier.allCases, id: \.self) { TierBadge(tier: $0) } }
}
