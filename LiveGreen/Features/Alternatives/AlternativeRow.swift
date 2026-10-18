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
                        summary.font(.caption.bold().monospacedDigit())
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

    /// How many of the metrics on the card get better and worse (`SwapMath.tally`, so it always matches the
    /// charts below), then the yearly carbon change whichever way it goes: a swap that adds carbon says so, in the
    /// warning color.
    @ViewBuilder private var summary: some View {
        let verdict = tallyText.map { Text($0).foregroundStyle(Theme.leaf) }
        let carbon = carbonChange.map { Text($0.text).foregroundStyle($0.saves ? Theme.leaf : Theme.warning) }
        switch (verdict, carbon) {
        case let (verdict?, carbon?): Text("\(verdict)\(Text(" · ").foregroundStyle(.secondary))\(carbon)")
        case let (verdict?, nil): verdict
        case let (nil, carbon?): carbon
        case (nil, nil): EmptyView()
        }
    }

    private var tallyText: String? {
        guard !isPlug else { return nil }
        let tally = SwapMath.tally(component, alternative)
        func metrics(_ count: Int) -> String { "\(count) metric\(count == 1 ? "" : "s")" }
        switch (tally.better, tally.worse) {
        case (0, 0): return nil
        case (let better, 0): return "Better on \(metrics(better)), none worse"
        case (0, let worse): return "Worse on \(metrics(worse))"
        case let (better, worse): return "Better on \(metrics(better)), worse on \(worse)"
        }
    }

    /// The yearly carbon change when it is a net change: "−14 lb CO₂e/yr" saved or "+3 lb CO₂e/yr" added.
    private var carbonChange: (text: String, saves: Bool)? {
        let baseline = (component.metrics[.carbon]?.value ?? 0) * SwapMath.yearlyFactor(.carbon, for: component)
        guard let saving = SwapMath.yearlySaving(.carbon, component: component, alternative: alternative),
              SwapMath.isNetChange(saving, baseline: baseline) else { return nil }
        let amount = DisplayUnits.carbon(kg: abs(saving.value))
        return saving.value > 0 ? ("−\(amount)/yr", true) : ("+\(amount)/yr", false)
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
