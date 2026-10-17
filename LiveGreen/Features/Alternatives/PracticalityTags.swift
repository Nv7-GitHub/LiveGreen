import SwiftUI
import GreenCore

/// Cost tier and effort capsules for an alternative.
struct PracticalityTags: View {
    let practicality: Practicality

    var body: some View {
        HStack(spacing: 6) {
            tag(practicality.cost.label, systemImage: "dollarsign.circle", color: practicality.cost.color)
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
    var label: String {
        switch self {
        case .lower: "Saves money"
        case .similar: "Similar cost"
        case .higher: "Costs more"
        }
    }

    var color: Color {
        switch self {
        case .lower: Theme.leaf
        case .similar: .secondary
        case .higher: Theme.warning
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
        PracticalityTags(practicality: Practicality(cost: .higher, effort: .hard))
    }
}
