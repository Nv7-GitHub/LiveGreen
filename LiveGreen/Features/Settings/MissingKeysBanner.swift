import SwiftUI

/// Names the required API keys that have no value (spec §11) and offers demo mode as a way out.
/// Hidden in demo mode, which needs no keys.
struct MissingKeysBanner: View {
    @Environment(AppModel.self) private var model
    /// Bumped by the caller after keys change so the Keychain is re-read.
    var revision = 0

    private var missing: [SecretKey] {
        _ = revision
        return model.flags.demoMode ? [] : model.secrets.missingRequiredKeys(for: model.flags.aiProvider)
    }

    var body: some View {
        if !missing.isEmpty {
            GlassCard(tint: Theme.warning.opacity(0.25)) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Missing API keys", systemImage: "key.slash")
                        .font(.headline)
                    Text(missing.map(\.displayName).formatted(.list(type: .and)) + " "
                         + (missing.count == 1 ? "isn't" : "aren't") + " set. Live scans fall back to offline data until you add "
                         + (missing.count == 1 ? "it" : "them") + " below.")
                        .font(.subheadline)
                    Button("Use demo mode", systemImage: "play.circle") { model.flags.demoMode = true }
                        .buttonStyle(.glass)
                }
            }
            .accessibilityIdentifier("settings.missingKeysBanner")
        }
    }
}
