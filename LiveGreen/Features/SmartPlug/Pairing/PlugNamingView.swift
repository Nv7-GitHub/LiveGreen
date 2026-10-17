import SwiftUI
import GreenCore

/// Step 5: name the plug and assign it to a scanned component.
struct PlugNamingView: View {
    let pairing: PairingModel
    let preselectedComponentID: UUID?
    let onSave: (PairedPlug) -> Void

    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var componentID: UUID?
    @State private var requiredHours = 3.0
    @State private var deadlineHour = GridOutlook.defaultDeadlineHour

    private var components: [Component] { model.plugCandidateComponents }
    private var selectedComponent: Component? { componentID.flatMap(model.scannedComponent(withID:)) }

    var body: some View {
        Form {
            if let device = pairing.device {
                Section("Device") {
                    LabeledContent("Model", value: device.model)
                    LabeledContent("Generation", value: "Gen\(device.generation)")
                    LabeledContent("Firmware", value: device.firmware)
                }
            }
            Section("Name") {
                TextField("E-bike charger", text: $name)
            }
            Section {
                Picker("Powers", selection: $componentID) {
                    Text("Nothing yet").tag(UUID?.none)
                    ForEach(components) { component in
                        Text(component.name).tag(UUID?.some(component.id))
                    }
                }
                Stepper(value: $requiredHours, in: 1...12, step: 1) {
                    LabeledContent("Charging per day", value: "\(Int(requiredHours)) h")
                }
                DeadlinePicker(hour: $deadlineHour)
            } header: {
                Text("Schedule")
            } footer: {
                Text(components.isEmpty
                     ? "Scan a charger, e-bike or appliance to assign it here."
                     : "LiveGreen picks the cleanest hours before your deadline.")
            }
            Section {
                Button("Save plug", systemImage: "checkmark", action: save)
                    .disabled(pairing.kind == nil || pairing.device == nil)
                    .accessibilityIdentifier("pairing.save")
            }
        }
        .navigationTitle("Name your plug")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
        .onChange(of: componentID) { _, _ in
            if let candidate = selectedComponent?.plugCandidate { requiredHours = Self.hours(for: candidate) }
        }
    }

    private func prefill() {
        guard name.isEmpty else { return }
        if let preselectedComponentID, components.contains(where: { $0.id == preselectedComponentID }) {
            componentID = preselectedComponentID
        } else if components.count == 1 {
            // Only one scanned load could use a plug, so assign it up front.
            componentID = components[0].id
        }
        let candidate = selectedComponent?.plugCandidate
        if let candidate { requiredHours = Self.hours(for: candidate) }
        name = candidate?.loadType.displayName ?? selectedComponent?.name ?? pairing.device?.name ?? "Smart plug"
    }

    private func save() {
        guard let kind = pairing.kind, let device = pairing.device else { return }
        let component = selectedComponent
        let plug = PairedPlug(name: name.isEmpty ? device.name ?? "Smart plug" : name,
                              kind: kind,
                              device: device,
                              componentID: component?.id,
                              componentName: component?.name,
                              candidate: component?.plugCandidate,
                              requiredHours: requiredHours,
                              deadlineHour: deadlineHour)
        PlugCenter.shared.add(plug, password: pairing.password)
        onSave(plug)
    }

    private static func hours(for candidate: PlugCandidate) -> Double {
        min(max(candidate.requiredHoursPerDay.rounded(.up), 1), 12)
    }
}
