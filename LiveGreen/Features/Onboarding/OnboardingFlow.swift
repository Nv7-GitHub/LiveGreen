import SwiftUI
import GreenCore

/// Onboarding questionnaire (spec §9): one glass card per question with progress, producing a `UserProfile`.
/// Also reused from Settings to edit the profile later.
struct OnboardingFlow: View {
    let initialProfile: UserProfile
    let onComplete: (UserProfile) -> Void
    /// When set (editing from Settings), a Cancel button is shown.
    var onCancel: (() -> Void)?

    @State private var profile: UserProfile
    @State private var step: OnboardingStep = .location
    @State private var movingForward = true

    init(initialProfile: UserProfile, onComplete: @escaping (UserProfile) -> Void, onCancel: (() -> Void)? = nil) {
        self.initialProfile = initialProfile
        self.onComplete = onComplete
        self.onCancel = onCancel
        _profile = State(initialValue: initialProfile)
    }

    private var isLast: Bool { step == OnboardingStep.allCases.last }

    var body: some View {
        VStack(spacing: 16) {
            header
            LiveEstimateCard(profile: profile, step: step)
            ScrollView {
                card
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)))
            }
            // Clipped so the question scrolls under, not over, the live estimate above it.
            .contentMargins(.vertical, 8, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            navigation
        }
        .padding()
        .background(backdrop)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LiveGreen", systemImage: "leaf.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.leaf)
                Spacer()
                if let onCancel {
                    Button("Cancel", action: onCancel).buttonStyle(.glass)
                }
            }
            ProgressView(value: Double(step.rawValue + 1), total: Double(OnboardingStep.allCases.count))
                .tint(Theme.leaf)
            Text("Question \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var card: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: step.symbol)
                    .font(.title)
                    .foregroundStyle(Theme.leaf)
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title).font(.title2.weight(.bold))
                    Text(step.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                OnboardingStepContent(step: step, profile: $profile)
            }
        }
    }

    private var navigation: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if step != .location {
                    Button("Back", systemImage: "chevron.left") { move(by: -1) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                Button(isLast ? "Finish" : "Next", systemImage: isLast ? "checkmark" : "chevron.right") {
                    isLast ? finish() : move(by: 1)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("onboarding.next")
            }
        }
    }

    private var backdrop: some View {
        LinearGradient(colors: [Theme.mint.opacity(0.45), Theme.leaf.opacity(0.15), .clear],
                       startPoint: .topLeading, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private func move(by offset: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + offset) else { return }
        movingForward = offset > 0
        withAnimation(.smooth) { step = next }
    }

    private func finish() {
        var completed = profile
        completed.region = USRegionLookup.resolved(profile.region)
        onComplete(completed)
    }
}

#Preview {
    OnboardingFlow(initialProfile: .default) { _ in }
}
