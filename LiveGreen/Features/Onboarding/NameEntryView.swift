import SwiftUI
import GreenCore

/// Stand-in for the onboarding questionnaire while `AppModel.usesFullOnboarding` is off: a pretend sign-up for a
/// LiveGreen account that joins the friends leaderboard. The only field is a display name, and nothing leaves
/// the device; the "creating" and "welcome" stages are for show.
struct NameEntryView: View {
    let initialName: String
    let onComplete: (String) -> Void

    private enum Stage { case form, creating, welcome }

    @State private var name: String
    @State private var stage = Stage.form
    @FocusState private var isFocused: Bool

    init(initialName: String, onComplete: @escaping (String) -> Void) {
        self.initialName = initialName
        self.onComplete = onComplete
        _name = State(initialValue: initialName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var handle: String { "@" + trimmed.lowercased().filter { $0.isLetter || $0.isNumber } }
    private let players = CohortModel.friendNames

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("LiveGreen", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Theme.leaf)
            Spacer()
            switch stage {
            case .form: form.transition(.opacity)
            case .creating, .welcome: progress.transition(.opacity)
            }
            Spacer()
            if stage == .form {
                Button(action: register) {
                    Label("Create account", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty)
                .accessibilityIdentifier("onboarding.next")
            }
        }
        .padding()
        .greeneryBackground(.onboarding)
        .onAppear { isFocused = true }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create your account").font(.largeTitle.weight(.bold))
                Text("Join the leaderboard and compete with your friends for the greenest footprint.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            competitors
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display name").font(.subheadline.weight(.semibold))
                    TextField("e.g. Alex Rivera", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .focused($isFocused)
                        .onSubmit(register)
                        .padding(12)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 12))
                        .accessibilityIdentifier("onboarding.name")
                    Text(trimmed.isEmpty ? "Other players see this on the leaderboard."
                                         : "You'll appear as \(trimmed) · \(handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Overlapping avatars of the people already on the board.
    private var competitors: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(players.prefix(5), id: \.self) { player in
                    InitialsAvatar(name: player)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
            }
            Text("\(firstName(players[0])), \(firstName(players[1])) and \(players.count - 2) others are already competing")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        VStack(spacing: 16) {
            if stage == .creating {
                ProgressView().controlSize(.large)
                Text("Creating your account…").font(.headline)
                Text("Adding \(handle) to the leaderboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.leaf)
                    .symbolEffect(.bounce, value: stage)
                Text("Welcome, \(firstName(trimmed))!").font(.title2.weight(.bold))
                Text("You're on the board with \(players.count) friends. Scan things to climb the ranks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private func register() {
        guard !trimmed.isEmpty, stage == .form else { return }
        isFocused = false
        withAnimation(.smooth) { stage = .creating }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.smooth) { stage = .welcome }
            try? await Task.sleep(for: .seconds(1.3))
            onComplete(trimmed)
        }
    }
}

#Preview {
    NameEntryView(initialName: "") { _ in }
}
