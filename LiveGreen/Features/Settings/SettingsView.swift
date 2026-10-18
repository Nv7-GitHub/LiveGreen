import SwiftUI
import GreenCore

/// Keys, scan mode, model choice, plug and demo toggles, profile editing and About (spec §3, §8.1, §11).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var keyDrafts: [SecretKey: String] = [:]
    @State private var keyRevision = 0
    @State private var isEditingProfile = false
    @State private var saveError: String?
    @State private var confirmsOnboardingReset = false
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                MissingKeysBanner(revision: keyRevision)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listSectionSpacing(0)

            Section("Your profile") {
                Button { isEditingProfile = true } label: {
                    ProfileSummaryRow(profile: model.profile)
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("settings.editProfile")
                Picker("Units", selection: $unitSystem) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.units")
                Button("Redo onboarding", systemImage: "arrow.counterclockwise") { confirmsOnboardingReset = true }
                    .accessibilityIdentifier("settings.resetOnboarding")
            }

            Section {
                Picker("Scan mode", selection: $model.flags.scanMode) {
                    ForEach(ScanMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Claude model", selection: $model.flags.modelChoice) {
                    ForEach(ClaudeModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.claudeModel")
                Toggle("Demo mode", isOn: $model.flags.demoMode)
            } header: {
                Text("Scanning")
            } footer: {
                Text("Claude identifies items, suggests swaps and researches spec sheets; Grok draws the greener image. Sonnet is the fast default. Demo mode replays bundled scenes (desk setup, meal, e-bike corner) with no network calls.")
            }

            Section {
                Toggle("Smart plug features", isOn: $model.flags.plugFeaturesEnabled)
                Toggle("Use mock plug", isOn: $model.flags.useMockPlug)
                    .disabled(!model.flags.plugFeaturesEnabled)
            } header: {
                Text("Smart plug")
            } footer: {
                Text(model.flags.plugFeaturesEnabled
                     ? "The mock plug simulates a Shelly plug's power draw for demos."
                     : "Plug recommendations and the Plugs tab are hidden.")
            }

            APIKeysSection(drafts: $keyDrafts, revision: $keyRevision)

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About & data sources", systemImage: "info.circle")
                }
                if let error = model.storageError ?? saveError {
                    Label(error, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { finish() }
            }
        }
        .confirmationDialog("Redo onboarding?", isPresented: $confirmsOnboardingReset, titleVisibility: .visible) {
            Button("Reset and start over", role: .destructive) { resetOnboarding() }
        } message: {
            Text("Your profile answers are cleared and onboarding starts again. Your scan history is kept.")
        }
        .sheet(isPresented: $isEditingProfile) {
            OnboardingFlow(initialProfile: model.profile,
                           onComplete: { profile in
                               var edited = profile
                               edited.onboardingCompleted = true
                               model.updateProfile(edited)
                               isEditingProfile = false
                           },
                           onCancel: { isEditingProfile = false })
        }
    }

    /// Settings is a sheet and onboarding is a full-screen cover on the root, so each presentation has to
    /// finish closing before the next one starts: the dialog, then this sheet, then onboarding opens.
    private func resetOnboarding() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            dismiss()
            try? await Task.sleep(for: .milliseconds(500))
            model.resetOnboarding()
        }
    }

    private func finish() {
        do {
            try KeyDrafts.saveAll(&keyDrafts, model: model)
            dismiss()
        } catch {
            saveError = "Couldn't save keys: \(error.localizedDescription)"
            keyRevision += 1
        }
    }
}

/// Compact summary of the onboarding answers.
private struct ProfileSummaryRow: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.leaf)
            VStack(alignment: .leading, spacing: 2) {
                Text(location).font(.headline)
                Text("\(profile.householdSize) in household · \(profile.diet.profileLabel) · \(travel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(profile.homeType.profileLabel), \(FloorAreaFormat.text(m2: profile.shownFloorAreaM2)) · \(profile.heatingLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Edit").font(.subheadline).foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 2)
    }

    private var travel: String {
        profile.commuteModes.isEmpty ? "No car or transit" : profile.commuteModes.map(\.profileLabel).joined(separator: " + ")
    }

    private var location: String {
        let country = Locale.current.localizedString(forRegionCode: profile.region.countryCode) ?? profile.region.countryCode
        return [profile.region.usState, country].compactMap { $0 }.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack { SettingsView() }.environment(AppModel.preview())
}
