import SwiftUI
import GreenCore

/// One component in the results list: name, share of the selected metric, and its value with tier.
struct ComponentRow: View {
    let component: Component
    let filter: ResultMetricFilter
    let share: Double
    let isSelected: Bool

    private var shown: Measured? { component.metrics[filter.shareMetric] }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: component.category.systemImage)
                .font(.title3)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(Theme.carbonShareTint(share).opacity(0.4)), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(component.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                ProgressView(value: share)
                    .tint(Theme.carbonShareTint(share))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let shown {
                    Text(shown.formatted).font(.subheadline.monospacedDigit()).lineLimit(1)
                    TierBadge(tier: shown.tier)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .glassCard(cornerRadius: 20, tint: isSelected ? Theme.leaf.opacity(0.2) : nil, interactive: true)
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("componentRow.\(component.name)")
    }

    private var subtitle: String {
        let identity = [component.identifiers.brand, component.identifiers.model].compactMap { $0 }.joined(separator: " ")
        let resolved = component.category.applicableMetrics.filter { component.metrics[$0] != nil }.count
        let coverage = "\(resolved)/\(component.category.applicableMetrics.count) metrics"
        let shareText = "\(Int((share * 100).rounded()))% of \(filter.shareMetric.displayName.lowercased())"
        return [identity.isEmpty ? component.category.displayName : identity,
                filter == .all ? coverage : shareText].joined(separator: " · ")
    }
}
