import SwiftUI

/// SecureFields for each API key. Saving writes a Keychain override (wins over Secrets.xcconfig).
struct APIKeysSection: View {
    @Environment(AppModel.self) private var model
    @Binding var drafts: [SecretKey: String]
    /// Incremented after every Keychain change so dependent views re-read it.
    @Binding var revision: Int
    @State private var error: String?

    var body: some View {
        Section {
            ForEach(SecretKey.allCases) { key in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(key.displayName).font(.subheadline.weight(.medium))
                        Spacer()
                        status(for: key)
                    }
                    HStack {
                        SecureField(model.secrets.hasOverride(for: key) ? "Replace saved key" : "Paste key", text: binding(for: key))
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { save(key) }
                        if model.secrets.hasOverride(for: key) {
                            Button("Remove", systemImage: "xmark.circle.fill", role: .destructive) { clear(key) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger)
            }
        } header: {
            Text("API keys")
        } footer: {
            Text("Keys entered here are stored in the Keychain and override Secrets.xcconfig. ENERGY STAR works without a token.")
        }
    }

    @ViewBuilder
    private func status(for key: SecretKey) -> some View {
        let _ = revision
        if model.secrets.hasOverride(for: key) {
            Label("Keychain", systemImage: "lock.fill").statusStyle(Theme.leaf)
        } else if model.secrets.infoPlistValue(for: key) != nil {
            Label("Config", systemImage: "doc.text").statusStyle(Theme.leaf)
        } else if key.isRequired(for: model.flags.aiProvider) {
            Label("Missing", systemImage: "exclamationmark.circle").statusStyle(Theme.warning)
        } else {
            Label("Optional", systemImage: "minus.circle").statusStyle(.secondary)
        }
    }

    private func binding(for key: SecretKey) -> Binding<String> {
        Binding(get: { drafts[key] ?? "" }, set: { drafts[key] = $0 })
    }

    private func save(_ key: SecretKey) {
        record { try KeyDrafts.save(key, from: &drafts, model: model) }
    }

    private func clear(_ key: SecretKey) {
        record { try KeyDrafts.write(nil, for: key, model: model) }
    }

    private func record(_ work: () throws -> Void) {
        do {
            try work()
            error = nil
        } catch {
            self.error = "Couldn't save key: \(error.localizedDescription)"
        }
        revision += 1
    }
}

/// Writes key drafts to the Keychain and rebuilds services so live clients pick them up.
enum KeyDrafts {
    /// Persists a non-empty draft for `key` and removes it from `drafts`.
    static func save(_ key: SecretKey, from drafts: inout [SecretKey: String], model: AppModel) throws {
        guard let draft = drafts[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !draft.isEmpty else { return }
        try write(draft, for: key, model: model)
        drafts[key] = nil
    }

    static func saveAll(_ drafts: inout [SecretKey: String], model: AppModel) throws {
        for key in SecretKey.allCases { try save(key, from: &drafts, model: model) }
    }

    static func write(_ value: String?, for key: SecretKey, model: AppModel) throws {
        try model.secrets.setOverride(value, for: key)
        model.refreshServices()
    }
}

private extension Label where Title == Text, Icon == Image {
    func statusStyle(_ style: some ShapeStyle) -> some View {
        font(.caption.weight(.semibold)).foregroundStyle(style)
    }
}
