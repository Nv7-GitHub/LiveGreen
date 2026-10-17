import SwiftUI
import GreenCore

/// One component in the results list: its pin number, name, source, value and share of the selected metric.
struct ComponentRow: View {
    let component: Component
    let number: Int
    let filter: ResultMetricFilter
    let share: Double
    let isSelected: Bool

    private var shown: Measured? { component.metrics[filter.shareMetric] }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.carbonShareTint(share).gradient, in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(component.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let shown {
                        Text(shown.formatted)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Capsule()
                        .fill(.fill.tertiary)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(Theme.carbonShareTint(share).gradient)
                                    .frame(width: max(4, geometry.size.width * share))
                            }
                        }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(isSelected ? AnyShapeStyle(Theme.leaf.opacity(0.15)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("componentRow.\(component.name)")
    }

    private var subtitle: String {
        let shareText = share > 0 && share < 0.005 ? "<1%" : "\(Int((share * 100).rounded()))%"
        guard filter != .all else {
            let resolved = component.category.applicableMetrics.filter { component.metrics[$0] != nil }.count
            return "\(resolved)/\(component.category.applicableMetrics.count) metrics"
        }
        return shareText
    }
}
