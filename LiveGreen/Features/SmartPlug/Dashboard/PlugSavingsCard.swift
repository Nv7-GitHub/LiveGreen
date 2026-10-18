import SwiftUI
import GreenCore

/// Measured savings so far (aenergy × hourly intensity) and the yearly estimate for the plan.
struct PlugSavingsCard: View {
    let plug: PairedPlug
    let outlook: GridOutlook?

    private var yearlyEstimateKg: Double? {
        guard let outlook, let schedule = plug.schedule,
              let dailyKWh = plug.candidate?.dailyKWh, dailyKWh > 0 else { return nil }
        return outlook.yearlySavingsKg(dailyKWh: dailyKWh, schedule: schedule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("CO₂ saved", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Theme.leaf)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let saved = DisplayUnits.smallCarbon(kg: plug.savings.savedKgCO2e)
                Text(Measured.format(saved.value))
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text(saved.unit).foregroundStyle(.secondary)
            }
            Text("Measured from \(Measured.format(plug.savings.measuredKWh)) kWh at each hour's grid intensity, versus the day's average.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let yearlyEstimateKg {
                Divider()
                LabeledContent("This plan, per year", value: "~\(DisplayUnits.carbon(kg: yearlyEstimateKg))")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Theme.leaf.opacity(0.12))
    }
}
