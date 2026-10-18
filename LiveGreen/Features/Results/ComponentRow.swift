import SwiftUI
import GreenCore

/// One component in the results list: its pin number, name, yearly value and share of the selected metric's yearly
/// total, and what that year assumes. Per-unit values (one serving, a whole life) are in the detail sheet.
struct ComponentRow: View {
    let component: Component
    let number: Int
    let filter: ResultMetricFilter
    /// The item's yearly value for the selected metric (carbon for "All"); nil leaves the value off.
    let yearly: Measured?
    /// Share (0–1) of the selected metric's yearly total.
    let share: Double
    /// What the item's year assumes, e.g. "2 servings a week" or "4-yr life".
    let assumption: String?
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(component.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let yearly, !yearly.isEffectivelyZero {
                        Text(yearly.formattedPerYear)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    Capsule()
                        .fill(.fill.tertiary)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(tint.gradient)
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

    /// Share of the selected metric's year (or the metric count for "All"), then what the year assumes.
    private var subtitle: String {
        let shareText = share > 0 && share < 0.005 ? "<1%" : "\(Int((share * 100).rounded()))%"
        let count = component.displayableMetrics.count
        let lead = filter != .all ? shareText : count == 1 ? "1 metric" : "\(count) metrics"
        return [lead, assumption].compactMap(\.self).joined(separator: " · ")
    }
}
