import SwiftUI
import GreenCore

/// Glass label floating over an anchored component: name, headline metric and its tier. The whole label is
/// the tap target (at least 44 pt tall).
struct ARComponentLabel: View {
    let component: Component
    /// Share of the scan's carbon (0–1), shown as the glass tint.
    let carbonShare: Double
    var isSelected = false
    let action: () -> Void

    private var shape: RoundedRectangle { .rect(cornerRadius: Theme.hotspotCornerRadius) }

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
            .frame(minHeight: 44)
            .frame(maxWidth: 220)
            // The glass sits outside the button, so without this only the text and icon took taps.
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.carbonShareTint(carbonShare).opacity(isSelected ? 0.6 : 0.35)).interactive(),
                     in: shape)
        .overlay {
            if isSelected { shape.strokeBorder(.white.opacity(0.9), lineWidth: 2).allowsHitTesting(false) }
        }
        .accessibilityLabel("\(component.name), \(component.metrics[.carbon]?.formatted ?? "no carbon value yet")")
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
