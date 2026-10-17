import SwiftUI
import GreenCore

/// Measured savings so far (aenergy × hourly intensity) and the yearly estimate for the plan.
struct PlugSavingsCard: View {
    let plug: PairedPlug
    let outlook: GridOutlook?
    let planner: any GreenHoursPlanning

    private var yearlyEstimateKg: Double? {
        guard let outlook, let schedule = plug.schedule,
              let dailyKWh = plug.candidate?.dailyKWh, dailyKWh > 0 else { return nil }
        return planner.yearlySavingsKg(dailyKWh: dailyKWh, schedule: schedule, forecast: outlook.forecast)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("CO₂ saved", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Theme.leaf)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Measured.format(plug.savings.savedKgCO2e * 1000))
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("g CO₂e").foregroundStyle(.secondary)
            }
            Text("Measured from \(Measured.format(plug.savings.measuredKWh)) kWh at each hour's grid intensity, versus the day's average.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let yearlyEstimateKg {
                Divider()
                LabeledContent("This plan, per year", value: "~\(Measured.format(yearlyEstimateKg)) kg CO₂e")
                    .font(.subheadline)
            }
        }
        .glassCard(tint: Theme.leaf.opacity(0.12))
    }
}
