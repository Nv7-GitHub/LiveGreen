import SwiftUI
import GreenCore

/// One selectable alternative. Smart-plug scheduling rows get a bolt badge and a pairing link.
struct AlternativeRow: View {
    let component: Component
    let alternative: Alternative
    let isSelected: Bool
    let onSelect: () -> Void
    var onPair: () -> Void = {}

    private var isPlug: Bool { alternative.kind == .smartPlugScheduling }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isPlug ? "bolt.badge.clock" : "leaf.arrow.triangle.circlepath")
                        .font(.title3)
                        .foregroundStyle(isPlug ? Color.yellow : Theme.leaf)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alternative.name).font(.subheadline.weight(.semibold))
                        Text(alternative.rationale).font(.caption).foregroundStyle(.secondary)
                        PracticalityTags(practicality: alternative.practicality)
                        if let saving = carbonSavingText {
                            Text(saving).font(.caption.bold().monospacedDigit()).foregroundStyle(Theme.leaf)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.leaf : .secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isPlug {
                Button("Pair a Shelly plug", systemImage: "powerplug", action: onPair)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.leading, 40)
            }
        }
        .padding(12)
        .background(isPlug ? Color.yellow.opacity(0.08) : .clear, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Theme.leaf.opacity(0.7) : .secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        }
    }

    private var carbonSavingText: String? {
        guard let saving = SwapMath.yearlySaving(.carbon, component: component, alternative: alternative),
              saving.value > 0 else { return nil }
        return "−\(Measured.format(saving.value)) kg CO₂e/yr"
    }
}

#Preview {
    let component = AlternativesPreviewData.result.components[0]
    VStack {
        ForEach(component.alternatives) { alternative in
            AlternativeRow(component: component, alternative: alternative,
                           isSelected: alternative.id == component.alternatives.first?.id, onSelect: {})
        }
    }
    .padding()
}
