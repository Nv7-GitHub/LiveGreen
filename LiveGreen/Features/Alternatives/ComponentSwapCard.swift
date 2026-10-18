import SwiftUI
import GreenCore

/// One component's 1–3 alternatives and, for the current pick, the comparison chart. Items offered exactly the same
/// swaps (four bikes, each "Buy a used bicycle") share one card: `others` take whatever the lead item takes, and the
/// chart is for one item.
struct ComponentSwapCard: View {
    let component: Component
    var others: [Component] = []
    let alternatives: [Alternative]
    let pick: Alternative?
    var charging: SmartPlugAlternative.ChargingCarbon?
    let onSelect: (Alternative) -> Void
    let onPair: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(component.name, systemImage: component.category.systemImage).font(.headline)
                    Spacer()
                    if let carbon = yearlyCarbon {
                        Text("\(carbon.formatted)/yr").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if !others.isEmpty {
                    Text("Same swap for \(others.map(\.name).joined(separator: ", ")).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(alternatives) { alternative in
                    AlternativeRow(component: component, alternative: alternative,
                                   isSelected: alternative.id == pick?.id, itemCount: 1 + others.count,
                                   onSelect: { onSelect(alternative) }, onPair: onPair)
                }
                if let pick {
                    Divider()
                    Text("Current vs. \(pick.kind == .smartPlugScheduling ? "scheduled charging" : pick.name)\(others.isEmpty ? "" : ", per item")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if pick.kind == .product, let note = sameFoodNote {
                        Text(note).font(.caption2).foregroundStyle(.secondary)
                    }
                    ComparisonChart(component: component, alternative: pick, charging: charging)
                } else {
                    Text(others.isEmpty ? "Keeping the original." : "Keeping the originals.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .animation(.smooth, value: pick?.id)
    }

    /// The items' carbon per year, the basis of the savings and charts below it (not one serving or the lifetime);
    /// all of them when the card covers several.
    private var yearlyCarbon: Measured? {
        guard component.displayable(.carbon) != nil, let lead = SwapMath.yearlyCarbon(of: component) else { return nil }
        return others.compactMap(SwapMath.yearlyCarbon).reduce(lead) { total, next in
            Measured(value: total.value + next.value, low: total.low + next.low, high: total.high + next.high,
                     unit: total.unit, tier: max(total.tier, next.tier), sources: total.sources)
        }
    }

    /// A food swap for a per-pack item covers the same amount of food at the same rate (`Alternative.onBasis`).
    private var sameFoodNote: String? {
        guard FoodServing.isPerPack(component), let basis = component.basisLabel,
              let packs = ImpactEngine().editableUsage(for: component).first(where: { $0.field == .packsPerWeek }) else {
            return nil
        }
        return "Both \(basis), \(UsageField.packsPerWeek.customLabel(packs.value)): the same amount of food."
    }
}

#Preview {
    let component = AlternativesPreviewData.result.components[0]
    ScrollView {
        ComponentSwapCard(component: component, alternatives: component.alternatives,
                          pick: component.alternatives.last, charging: AlternativesPreviewData.charging, onSelect: { _ in }, onPair: {})
            .padding()
    }
}
