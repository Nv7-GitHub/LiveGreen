import SwiftUI
import GreenCore

/// Stand-in for the onboarding questionnaire while `AppModel.usesFullOnboarding` is off: a pretend sign-up for a
/// LiveGreen account that joins the friends leaderboard. The display name stays on the device. An optional phone
/// number turns on meal nudges: it is assigned a Photon iMessage line, and the user texts that line once so it
/// may reply (`NudgeCenter`).
struct NameEntryView: View {
    let initialName: String
    let onComplete: (String) -> Void

    @Environment(AppModel.self) private var app

    private enum Stage { case form, creating, texting, welcome }
    private enum Field { case name, phone }

    @State private var name: String
    @State private var phone = ""
    @State private var stage = Stage.form
    @State private var phoneError: String?
    @State private var lineNumber: String?
    @State private var checking = false
    @State private var checkNote: String?
    @FocusState private var focus: Field?

    init(initialName: String, onComplete: @escaping (String) -> Void) {
        self.initialName = initialName
        self.onComplete = onComplete
        _name = State(initialValue: initialName)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var handle: String { "@" + trimmed.lowercased().filter { $0.isLetter || $0.isNumber } }
    private var phoneEntered: Bool { !phone.trimmingCharacters(in: .whitespaces).isEmpty }
    private var phoneValid: Bool { !phoneEntered || PhotonClient.e164(phone) != nil }
    private let players = CohortModel.friendNames

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("LiveGreen", systemImage: "leaf.fill")
                .font(.headline)
                .foregroundStyle(Theme.leaf)
            // Scrolls so the fields can rise above the keyboard; centred while everything fits.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        switch stage {
                        case .form: form.transition(.opacity)
                        case .texting: texting.transition(.opacity)
                        case .creating, .welcome: progress.transition(.opacity)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
            }
            if stage == .form {
                Button(action: register) {
                    Label("Create account", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty || !phoneValid)
                .accessibilityIdentifier("onboarding.next")
            }
        }
        .padding()
        .greeneryBackground(.onboarding)
        .toolbar {
            // The phone pad has no return key; this puts the keyboard away.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .accessibilityIdentifier("onboarding.keyboardDone")
            }
        }
        .onAppear { focus = .name }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create your account").font(.largeTitle.weight(.bold))
            competitors
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display name").font(.subheadline.weight(.semibold))
                        TextField("e.g. Alex Rivera", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .name)
                            .onSubmit { focus = .phone }
                            .padding(12)
                            .background(.background.opacity(0.6), in: .rect(cornerRadius: 12))
                            .accessibilityIdentifier("onboarding.name")
                        Text(trimmed.isEmpty ? "Other players see this on the leaderboard."
                                             : "You'll appear as \(trimmed) · \(handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phone number").font(.subheadline.weight(.semibold))
                        TextField("(617) 555-0123", text: $phone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .focused($focus, equals: .phone)
                            .padding(12)
                            .background(.background.opacity(0.6), in: .rect(cornerRadius: 12))
                            .accessibilityIdentifier("onboarding.phone")
                        if !phoneValid {
                            Label("Include the area code, e.g. (617) 555-0123.", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
        }
    }

    /// The step between the account and the welcome: text the assigned line once so it may reply.
    private var texting: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.leaf)
                Text("Turn on meal nudges").font(.largeTitle.weight(.bold))
                Text("Send one text to your LiveGreen number. iMessage only lets it write to you once you've messaged it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    if let lineNumber {
                        Text("Text START to").font(.caption).foregroundStyle(.secondary)
                        Text(PhoneFormat.pretty(lineNumber))
                            .font(.title.weight(.bold).monospacedDigit())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("onboarding.lineNumber")
                        if let url = URL(string: "sms:\(lineNumber)&body=START") {
                            Link(destination: url) {
                                Label("Open Messages", systemImage: "arrow.up.message")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                    } else if let phoneError {
                        Label(phoneError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Getting your LiveGreen number…").font(.subheadline)
                        }
                    }
                    if let checkNote {
                        Text(checkNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 10) {
                Button(action: checkTexted) {
                    Label(checking ? "Checking…" : "I've sent it", systemImage: "checkmark.message")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(lineNumber == nil || checking)
                .accessibilityIdentifier("onboarding.texted")
                Button("Skip for now") { welcome() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.skipTexting")
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
        guard !trimmed.isEmpty, phoneValid, stage == .form else { return }
        focus = nil
        withAnimation(.smooth) { stage = .creating }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            guard phoneEntered else { return welcome() }
            withAnimation(.smooth) { stage = .texting }
            do {
                lineNumber = try await app.nudges.register(phone: phone, name: trimmed, photon: app.services.photon)
            } catch {
                phoneError = NudgeCenter.describe(error) + " You can set it up later in the Nudges tab."
            }
        }
    }

    private func checkTexted() {
        checking = true
        checkNote = nil
        Task {
            // The message can take a few seconds to reach Photon.
            for attempt in 0..<4 {
                if await app.nudges.checkActivation(photon: app.services.photon) {
                    checking = false
                    return welcome()
                }
                if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
            }
            checking = false
            checkNote = app.nudges.setupError ?? "Haven't seen your text yet. Give it a moment and try again, or skip and finish this in the Nudges tab."
        }
    }

    private func welcome() {
        withAnimation(.smooth) { stage = .welcome }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            onComplete(trimmed)
        }
    }
}

#Preview {
    NameEntryView(initialName: "") { _ in }
        .environment(AppModel.preview())
}
