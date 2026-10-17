import SwiftUI
import GreenCore

/// Live `Switch.GetStatus` readout with the manual on/off override, or the offline state.
struct PlugStatusCard: View {
    let plug: PairedPlug
    let status: PlugStatus?
    let isSwitching: Bool
    let onToggle: (Bool) -> Void
    let onUseMock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(plug.name, systemImage: plug.isMock ? "cpu" : "powerplug.fill")
                    .font(.headline)
                Spacer()
                Text(plug.hostDescription).font(.caption).foregroundStyle(.secondary)
            }
            if let offlineSince = plug.offlineSince {
                offline(since: offlineSince)
            } else if let status {
                readings(status)
            } else {
                ProgressView("Connecting…")
            }
        }
        .glassCard()
    }

    private func readings(_ status: PlugStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                reading(Measured.format(status.activePowerW), "W", "Power now")
                reading(Measured.format(status.totalEnergyWh / 1000), "kWh", "Energy total")
                if let temperature = status.temperatureC {
                    reading(Measured.format(temperature), "°C", "Temp")
                }
            }
            Toggle(isOn: Binding(get: { status.isOn }, set: onToggle)) {
                Text(status.isOn ? "On" : "Off").font(.subheadline.weight(.semibold))
                Text("Manual override until the next scheduled switch").font(.caption).foregroundStyle(.secondary)
            }
            .disabled(isSwitching)
        }
    }

    private func reading(_ value: String, _ unit: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2.weight(.semibold).monospacedDigit())
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func offline(since date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Offline since \(date.formatted(date: .omitted, time: .shortened))", systemImage: "wifi.exclamationmark")
                .foregroundStyle(Theme.warning)
            Text("Schedules already on the plug keep running. Check the plug is powered and on this Wi-Fi.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !plug.isMock {
                Button("Use the mock plug", systemImage: "cpu", action: onUseMock)
                    .buttonStyle(.glass)
            }
        }
    }
}
