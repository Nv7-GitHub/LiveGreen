import SwiftUI
import GreenCore

/// "That's like driving 1,200 miles in an average gas car!" under a number, so it reads as something people know.
/// The comparison comes from `Equivalences` and is seeded by `context` and the day, so it changes between items,
/// metrics and days but holds still while on screen. Shows nothing when no comparison reads well for the amount.
struct EquivalenceCallout: View {
    /// Read in `body` so miles and gallons switch with Settings.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
    let metric: MetricKey
    /// Canonical units (kg CO₂e, L, m², kWh, g).
    let amount: Double
    /// What the number belongs to ("scan-<id>|carbon"); picks the comparison.
    let context: String
    var framing: Equivalence.Framing = .amount

    private var equivalence: Equivalence? {
        Equivalences.pick(for: metric, amount: amount, imperial: unitSystem == .imperial,
                          seed: Equivalences.seed(context))
    }

    var body: some View {
        if let equivalence {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: equivalence.systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.leaf)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(equivalence.sentence(framing))
                        .font(.subheadline.weight(.semibold))
                    Text(equivalence.source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.leaf.opacity(0.1), in: .rect(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("equivalence")
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        EquivalenceCallout(metric: .carbon, amount: 1_500, context: "preview")
        EquivalenceCallout(metric: .water, amount: 4_000, context: "preview", framing: .saving)
    }
    .padding()
}
