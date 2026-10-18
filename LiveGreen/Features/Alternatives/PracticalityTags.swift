import SwiftUI
import GreenCore

/// Cost tier and effort capsules for an alternative.
struct PracticalityTags: View {
    /// What the cost tier is measured against, so a purchase never reads as "saves money" next to keeping what the
    /// user already has (S11: "Buy a used bicycle · Saves money", "Saves money" on the smart plug).
    enum Framing {
        /// Bought again and again (food, cups, packaging): the cost over a year of buying it.
        case ongoing
        /// Buying an item in place of a durable one the user owns: cheaper or pricier than buying that new.
        case replacement
        /// An extra bought on top of the item (the smart plug).
        case addOn
    }

    let practicality: Practicality
    var framing: Framing = .ongoing

    var body: some View {
        HStack(spacing: 6) {
            tag(practicality.cost.label(framing), systemImage: "dollarsign.circle", color: practicality.cost.color(framing))
            tag(practicality.effort.label, systemImage: "figure.walk", color: practicality.effort.color)
        }
    }

    private func tag(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: .capsule)
    }
}

extension Practicality.CostTier {
    func label(_ framing: PracticalityTags.Framing) -> String {
        switch (framing, self) {
        case (.addOn, _): "One-time cost"
        case (.replacement, .lower): "Cheaper than new"
        case (.replacement, .similar): "Similar price to new"
        case (.replacement, .higher): "Pricier than new"
        case (.ongoing, .lower): "Saves money"
        case (.ongoing, .similar): "Similar cost"
        case (.ongoing, .higher): "Costs more"
        }
    }

    func color(_ framing: PracticalityTags.Framing) -> Color {
        switch (framing, self) {
        case (.addOn, _), (_, .similar): .secondary
        case (_, .lower): Theme.leaf
        case (_, .higher): Theme.warning
        }
    }
}

extension Practicality.Effort {
    var label: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Some effort"
        case .hard: "Hard"
        }
    }

    var color: Color {
        switch self {
        case .easy: Theme.leaf
        case .moderate: .secondary
        case .hard: Theme.warning
        }
    }
}

#Preview {
    VStack {
        PracticalityTags(practicality: Practicality(cost: .lower, effort: .easy))
        PracticalityTags(practicality: Practicality(cost: .lower, effort: .moderate), framing: .replacement)
        PracticalityTags(practicality: Practicality(cost: .higher, effort: .hard))
    }
}
