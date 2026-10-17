import SwiftUI
import GreenCore

/// Today's green hours plus the controls that shape the plan and write it to the plug.
struct PlugScheduleCard: View {
    let plug: PairedPlug
    let dashboard: PlugDashboardModel
    let components: [Component]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today's green hours").font(.headline)
                Spacer()
                if let schedule = dashboard.previewSchedule, let intensity = schedule.expectedIntensity {
                    Text("avg \(Measured.format(intensity)) g/kWh")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if let outlook = dashboard.outlook {
                GreenHoursTimeline(forecast: outlook.forecast, onHours: Set(dashboard.previewSchedule?.onHours ?? []))
            }
            controls
            applyRow
        }
        .glassCard()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            LabeledContent {
                componentPicker.labelsHidden()
            } label: {
                Label("Powers", systemImage: "bolt.car")
            }
            Stepper(value: binding(\.requiredHours), in: 1...12, step: 1) {
                Label("Charging \(Int(plug.requiredHours)) h a day", systemImage: "hourglass")
            }
            LabeledContent {
                DeadlinePicker(hour: binding(\.deadlineHour)).labelsHidden()
            } label: {
                Label("Charged by", systemImage: "alarm")
            }
        }
        .font(.subheadline)
    }

    private var componentPicker: some View {
        Picker("Powers", selection: componentBinding) {
            Text("None").tag(UUID?.none)
            ForEach(components) { component in
                Text(component.name).tag(UUID?.some(component.id))
            }
            if let id = plug.componentID, !components.contains(where: { $0.id == id }) {
                Text(plug.componentName ?? "Assigned item").tag(UUID?.some(id))
            }
        }
    }

    private var applyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await dashboard.applySchedule() }
            } label: {
                HStack {
                    if dashboard.isApplying { ProgressView() } else { Image(systemName: "calendar.badge.clock") }
                    Text("Apply schedule to plug")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(dashboard.outlook == nil || dashboard.isApplying)

            if let applied = plug.scheduleAppliedAt, let schedule = plug.schedule {
                Text("On the plug since \(applied.formatted(date: .abbreviated, time: .shortened)): \(Self.describe(schedule))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Not written yet. Once applied, the plug follows the plan even with the app closed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var componentBinding: Binding<UUID?> {
        Binding(get: { plug.componentID }, set: { id in
            let component = components.first { $0.id == id }
            dashboard.update { plug in
                plug.componentID = component?.id
                plug.componentName = component?.name
                plug.candidate = component?.plugCandidate
                if let candidate = component?.plugCandidate {
                    plug.requiredHours = min(max(candidate.requiredHoursPerDay.rounded(.up), 1), 12)
                }
            }
        })
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PairedPlug, Value>) -> Binding<Value> {
        Binding(get: { plug[keyPath: keyPath] }, set: { value in dashboard.update { $0[keyPath: keyPath] = value } })
    }

    static func describe(_ schedule: PlugSchedule) -> String {
        schedule.windows
            .map { "\(HourFormatting.label($0.lowerBound))–\(HourFormatting.label($0.upperBound))" }
            .joined(separator: ", ")
    }
}
