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
            VStack(alignment: .leading, spacing: 16) {
                SingleChoiceChips(selection: $profile.commuteMode)
                if profile.commuteMode != .remote {
                    DistanceSlider(kmPerWeek: $profile.commuteKmPerWeek)
                }
            }
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
            Button("Fewer", systemImage: "minus") { size = max(1, size - 1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .disabled(size <= 1)
            VStack(spacing: 0) {
                Text("\(size)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(size)))
                Text(size == 1 ? "person" : "people").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(minWidth: 90)
            Button("More", systemImage: "plus") { size = min(12, size + 1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .disabled(size >= 12)
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
}

private struct DistanceSlider: View {
    @Binding var kmPerWeek: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Distance per week").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(kmPerWeek)) km").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $kmPerWeek, in: 0...500, step: 5)
                .accessibilityLabel("Commute distance per week")
                .accessibilityValue("\(Int(kmPerWeek)) kilometers")
        }
    }
}
