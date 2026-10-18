import SwiftUI

/// Top of the Leaderboard: the name entered at first launch, presented as a LiveGreen account. The account is
/// pretend (no sign-up or server); `isCreated` flips after a short "creating" step the first time.
struct AccountCard: View {
    let name: String
    let isCreated: Bool

    /// A handle derived from the name, e.g. "Ada Lovelace" → "@adalovelace".
    private var handle: String {
        "@" + name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                InitialsAvatar(name: name, isUser: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).lineLimit(1)
                    if isCreated {
                        Label(handle, systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.leaf)
                            .lineLimit(1)
                            .transition(.opacity)
                    } else {
                        Text("Creating your LiveGreen account…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                Spacer()
                if !isCreated { ProgressView() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("leaderboard.account")
    }
}

#Preview {
    VStack {
        AccountCard(name: "Ada Lovelace", isCreated: false)
        AccountCard(name: "Ada Lovelace", isCreated: true)
    }
    .padding()
}
