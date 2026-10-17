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
            }

            Section {
                Picker("Scan mode", selection: $model.flags.scanMode) {
                    ForEach(ScanMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("AI provider", selection: $model.flags.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.aiProvider")
                if model.flags.aiProvider == .claude {
                    Picker("Claude model", selection: $model.flags.modelChoice) {
                        ForEach(ClaudeModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Toggle("Demo mode", isOn: $model.flags.demoMode)
            } header: {
                Text("Scanning")
            } footer: {
                Text("The AI provider identifies items, suggests swaps and researches spec sheets. Demo mode replays bundled scenes (desk setup, meal, e-bike corner) with no network calls.")
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
                LabeledContent("Peer network", value: "Simulated")
                if let error = model.storageError ?? saveError {
                    Label(error, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(Theme.danger)
                }
            } footer: {
                Text("Compare-tab friends are a simulated network sampled from your modeled peer cohort.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { finish() }
            }
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
                Text("\(profile.householdSize) in household · \(profile.diet.profileLabel) · \(profile.commuteModes.map(\.profileLabel).joined(separator: " + "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(profile.homeType.profileLabel) · \(profile.heating.profileLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Edit").font(.subheadline).foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 2)
    }

    private var location: String {
        let country = Locale.current.localizedString(forRegionCode: profile.region.countryCode) ?? profile.region.countryCode
        return [profile.region.usState, country].compactMap { $0 }.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack { SettingsView() }.environment(AppModel.preview())
}
