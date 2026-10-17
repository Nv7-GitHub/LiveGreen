import SwiftUI
import GreenCore

/// The answer controls for one onboarding step, bound to the draft profile.
struct OnboardingStepContent: View {
    let step: OnboardingStep
    @Binding var profile: UserProfile

    var body: some View {
        switch step {
        case .location:
            LocationStepView(region: $profile.region)
        case .household:
            HouseholdPicker(size: $profile.householdSize)
        case .diet:
            SingleChoiceChips(selection: $profile.diet)
        case .commute:
            CommutePlanner(distances: $profile.commuteKmPerWeekByMode)
        case .home:
            VStack(alignment: .leading, spacing: 16) {
                SingleChoiceChips(selection: $profile.homeType)
                Text("Heating").font(.subheadline.weight(.semibold))
                SingleChoiceChips(selection: $profile.heating)
            }
        case .clothing:
            SingleChoiceChips(selection: $profile.clothingHabit)
        case .chargers:
            VStack(alignment: .leading, spacing: 10) {
                MultiChoiceChips(selection: $profile.chargingItems)
                Text(profile.chargingItems.isEmpty ? "None selected — that's fine." : "\(profile.chargingItems.count) selected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct HouseholdPicker: View {
    @Binding var size: Int

    var body: some View {
        HStack(spacing: 20) {
            stepButton("Fewer", systemImage: "minus") { size = max(1, size - 1) }
                .disabled(size <= 1)
                .accessibilityIdentifier("onboarding.household.fewer")
            VStack(spacing: 0) {
                Text("\(size)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(size)))
                    .accessibilityIdentifier("onboarding.household.count")
                Text(size == 1 ? "person" : "people").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(minWidth: 90)
            stepButton("More", systemImage: "plus") { size = min(12, size + 1) }
                .disabled(size >= 12)
                .accessibilityIdentifier("onboarding.household.more")
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: size)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(size)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: size = min(12, size + 1)
            case .decrement: size = max(1, size - 1)
            @unknown default: break
            }
        }
    }

    /// A round glass stepper button, comfortably over 44 pt (the icon-only default was about 30 pt tall).
    private func stepButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(title)
    }
}

/// Stored in km; shown and edited in miles in the imperial unit system.
struct DistanceSlider: View {
    var title = "Distance per week"
    @Binding var kmPerWeek: Double

    private static let kmPerMile = 1.609_34
    private var imperial: Bool { DisplayUnits.system == .imperial }

    private var shown: Binding<Double> {
        Binding(get: { imperial ? kmPerWeek / Self.kmPerMile : kmPerWeek },
                set: { kmPerWeek = imperial ? $0 * Self.kmPerMile : $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(shown.wrappedValue.rounded())) \(imperial ? "mi" : "km") a week")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: shown, in: 0...(imperial ? 300 : 500), step: 5)
                .tint(Theme.leaf)
                .accessibilityLabel("\(title) per week")
                .accessibilityValue("\(Int(shown.wrappedValue.rounded())) \(imperial ? "miles" : "kilometers")")
        }
    }
}
