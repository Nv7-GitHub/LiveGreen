import SwiftUI
import GreenCore

/// Glass label floating over an anchored component: name, headline metric and its tier.
struct ARComponentLabel: View {
    let component: Component
    /// Share of the scan's carbon (0–1), shown as the glass tint.
    let carbonShare: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: component.category.systemImage)
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(component.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let carbon = component.metrics[.carbon] {
                        Text(carbon.formatted)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let tier = component.metrics[.carbon]?.tier {
                    TierBadge(tier: tier)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 220)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.carbonShareTint(carbonShare).opacity(0.35)).interactive(),
                     in: .rect(cornerRadius: Theme.hotspotCornerRadius))
        .accessibilityLabel("\(component.name), \(component.metrics[.carbon]?.formatted ?? "no carbon value yet")")
        .accessibilityHint("Opens details")
    }
}
