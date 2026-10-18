import SwiftUI

/// iOS 26 floating glass tab bar: Scan, History, Leaderboard, Nudges and Plugs (when enabled).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Scan", systemImage: "viewfinder", value: AppTab.scan) {
                ScanTab()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryTab() }
            }
            Tab("Leaderboard", systemImage: "trophy", value: AppTab.compare) {
                CompareTab()
            }
            Tab("Nudges", systemImage: "message.badge", value: AppTab.nudges) {
                NudgesTab()
            }
            if model.flags.plugFeaturesEnabled {
                Tab("Plugs", systemImage: "powerplug", value: AppTab.plugs) {
                    PlugsTab()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: .constant(model.needsOnboarding)) {
            if AppModel.usesFullOnboarding {
                OnboardingFlow(initialProfile: model.profile) { model.completeOnboarding(with: $0) }
            } else {
                NameEntryView(initialName: model.displayName) { model.completeOnboarding(withName: $0) }
            }
        }
        .onChange(of: model.flags.plugFeaturesEnabled) { _, enabled in
            if !enabled, model.selectedTab == .plugs { model.selectedTab = .scan }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in refreshPlugs(for: phase) }
        .task(id: scenePhase) { await sendDueNudges() }
    }

    /// While the app is open, sends any meal nudge whose time has come, checking every half minute. With no server,
    /// this is the only way a scheduled nudge goes out on its own; the Nudges tab can send one now.
    private func sendDueNudges() async {
        guard scenePhase == .active else { return }
        model.refreshNudges()
        while !Task.isCancelled {
            await model.nudges.sendDue(photon: model.services.photon)
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// Spec §8.3: re-plan paired plugs whenever the app comes to the foreground, and queue the best-effort
    /// background refresh when it leaves, whether or not the Plugs tab was ever opened.
    private func refreshPlugs(for phase: ScenePhase) {
        guard model.flags.plugFeaturesEnabled else { return }
        switch phase {
        case .active:
            GridOutlook.warm(grid: model.services.grid, profile: model.profile)
            Task { await PlugCenter.shared.replanAll(services: model.services, profile: model.profile) }
            BackgroundRefresh.schedule()
        case .background:
            BackgroundRefresh.schedule()
        default:
            break
        }
    }
}

#Preview {
    RootView().environment(AppModel.preview())
}
