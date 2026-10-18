import SwiftUI

/// Stand-in for the onboarding questionnaire while `AppModel.usesFullOnboarding` is off: asks only for a name,
/// which the Leaderboard shows on your row and account card. The profile keeps its default answers.
struct NameEntryView: View {
    let initialName: String
    let onComplete: (String) -> Void

    @State private var name: String
    @FocusState private var isFocused: Bool

    init(initialName: String, onComplete: @escaping (String) -> Void) {
        self.initialName = initialName
        self.onComplete = onComplete
        _name = State(initialValue: initialName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("LiveGreen", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Theme.leaf)
            Spacer()
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title)
                        .foregroundStyle(Theme.leaf)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's your name?").font(.title2.weight(.bold))
                        Text("It's how you'll show up on the leaderboard with your friends.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.continue)
                        .focused($isFocused)
                        .onSubmit(finish)
                        .padding(12)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 12))
                        .accessibilityIdentifier("onboarding.name")
                }
            }
            Spacer()
            Button(action: finish) {
                Label("Continue", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(trimmed.isEmpty)
            .accessibilityIdentifier("onboarding.next")
        }
        .padding()
        .background(
            LinearGradient(colors: [Theme.mint.opacity(0.45), Theme.leaf.opacity(0.15), .clear],
                           startPoint: .topLeading, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear { isFocused = true }
    }

    private func finish() {
        guard !trimmed.isEmpty else { return }
        onComplete(trimmed)
    }
}

#Preview {
    NameEntryView(initialName: "") { _ in }
}
