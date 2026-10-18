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
            // One scroll view per question, overlapping in a ZStack while they slide: inside a single scroll view
            // the outgoing and incoming cards stacked vertically mid-transition, and a question opened at the
            // previous one's scroll offset.
            ZStack {
                ScrollView {
                    card
                }
                // Clipped so the question scrolls under, not over, the live estimate above it.
                .contentMargins(.vertical, 8, for: .scrollContent)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxHeight: .infinity)
            navigation
        }
        .padding()
        .greeneryBackground(.onboarding)
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

    /// Outside the scroll view, so Back and Next stay put above the keyboard and long questions. Next fills the
    /// rest of the row for a large target.
    private var navigation: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if step != .location {
                    Button("Back", systemImage: "chevron.left") { move(by: -1) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .accessibilityIdentifier("onboarding.back")
                }
                Button {
                    isLast ? finish() : move(by: 1)
                } label: {
                    Label(isLast ? "Finish" : "Next", systemImage: isLast ? "checkmark" : "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.next")
            }
        }
    }

    private func move(by offset: Int) {
        guard let next = OnboardingStep(rawValue: step.rawValue + offset) else { return }
        guard movingForward != (offset > 0) else {
            withAnimation(.smooth) { step = next }
            return
        }
        // The outgoing card takes its removal edge from its last render, so on a change of direction let the
        // new direction render for a frame before the step changes; otherwise the first Back after Next slid
        // both cards the same way.
        movingForward = offset > 0
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.smooth) { step = next }
        }
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
