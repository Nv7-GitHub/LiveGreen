import SwiftUI
import GreenCore

/// Keys, scan mode, model choice, plug on/off and mock toggles (spec §3, §11).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var keyDrafts: [SecretKey: String] = [:]

    var body: some View {
        @Bindable var model = model
        Form {
            if !model.secrets.missingRequiredKeys.isEmpty && !model.flags.demoMode {
                Section {
                    Label("Missing: " + model.secrets.missingRequiredKeys.map(\.rawValue).joined(separator: ", "),
                          systemImage: "key.slash")
                        .foregroundStyle(Theme.warning)
                }
            }
            Section("Scanning") {
                Picker("Scan mode", selection: $model.flags.scanMode) {
                    ForEach(ScanMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Model", selection: $model.flags.modelChoice) {
                    ForEach(ClaudeModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Demo mode (offline fixtures)", isOn: $model.flags.demoMode)
            }
            Section {
                Toggle("Smart plug features", isOn: $model.flags.plugFeaturesEnabled)
                Toggle("Use mock plug", isOn: $model.flags.useMockPlug)
                    .disabled(!model.flags.plugFeaturesEnabled)
            } header: {
                Text("Smart plug")
            }
            Section {
                ForEach(SecretKey.allCases) { key in
                    SecureField(key.displayName, text: binding(for: key))
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { saveKey(key) }
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("Keys entered here are stored in the Keychain and override Secrets.xcconfig.")
            }
            Section("About") {
                LabeledContent("Peer network", value: "Simulated")
                Text("Friends on the leaderboard are a simulated network sampled from your modeled peer cohort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error = model.storageError {
                    Label(error, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") {
                    SecretKey.allCases.forEach(saveKey)
                    dismiss()
                }
            }
        }
    }

    private func binding(for key: SecretKey) -> Binding<String> {
        Binding(get: { keyDrafts[key] ?? "" }, set: { keyDrafts[key] = $0 })
    }

    private func saveKey(_ key: SecretKey) {
        guard let draft = keyDrafts[key], !draft.isEmpty else { return }
        try? model.secrets.setOverride(draft, for: key)
        keyDrafts[key] = nil
        model.refreshServices()
    }
}

#Preview {
    NavigationStack { SettingsView() }.environment(AppModel.preview())
}
