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
                        if let summary {
                            Text(summary).font(.caption.bold().monospacedDigit()).foregroundStyle(Theme.leaf)
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

    /// GreenScore's average gain across every metric that counts, then the yearly carbon saving when it is a
    /// net change.
    private var summary: String? {
        var parts: [String] = []
        if !isPlug {
            let assessment = GreenScore.assess(alternative, replacing: component, engine: SwapMath.engine)
            let percent = Int((assessment.averageImprovement * 100).rounded())
            if percent > 0 {
                let count = assessment.changes.count
                parts.append("\(percent)% greener across \(count) metric\(count == 1 ? "" : "s")")
            }
        }
        let baseline = (component.metrics[.carbon]?.value ?? 0) * SwapMath.yearlyFactor(.carbon, for: component)
        if let saving = SwapMath.yearlySaving(.carbon, component: component, alternative: alternative),
           saving.value > 0, SwapMath.isNetChange(saving, baseline: baseline) {
            parts.append("−\(DisplayUnits.carbon(kg: saving.value))/yr")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
