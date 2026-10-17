import SwiftUI
import GreenCore

/// Onboarding questionnaire (spec §9) producing a `UserProfile`.
struct OnboardingFlow: View {
    let initialProfile: UserProfile
    let onComplete: (UserProfile) -> Void
    @State private var profile: UserProfile

    init(initialProfile: UserProfile, onComplete: @escaping (UserProfile) -> Void) {
        self.initialProfile = initialProfile
        self.onComplete = onComplete
        _profile = State(initialValue: initialProfile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Where you live") {
                    TextField("Country code", text: $profile.region.countryCode)
                        .textInputAutocapitalization(.characters)
                    TextField("ZIP / postal code", text: Binding(
                        get: { profile.region.postalCode ?? "" },
                        set: { profile.region.postalCode = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.numbersAndPunctuation)
                    Stepper("Household: \(profile.householdSize)", value: $profile.householdSize, in: 1...12)
                }
                Section("Habits") {
                    Picker("Diet", selection: $profile.diet) {
                        ForEach(Diet.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Commute", selection: $profile.commuteMode) {
                        ForEach(CommuteMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Clothing", selection: $profile.clothingHabit) {
                        ForEach(ClothingHabit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            .navigationTitle("Welcome to LiveGreen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", systemImage: "checkmark") { onComplete(profile) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

#Preview {
    OnboardingFlow(initialProfile: .default) { _ in }
}
