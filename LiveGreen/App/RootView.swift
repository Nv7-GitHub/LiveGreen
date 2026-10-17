import SwiftUI

/// iOS 26 floating glass tab bar: Scan, History, Compare, Plugs (when enabled) and a search-role tab.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Scan", systemImage: "viewfinder", value: AppTab.scan) {
                ScanTab()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryTab() }
            }
            Tab("Compare", systemImage: "chart.bar.xaxis", value: AppTab.compare) {
                CompareTab()
            }
            if model.flags.plugFeaturesEnabled {
                Tab("Plugs", systemImage: "powerplug", value: AppTab.plugs) {
                    PlugsTab()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack {
                    HistoryTab(searchText: searchText)
                        .searchable(text: $searchText, prompt: "Search scans")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: .constant(model.needsOnboarding)) {
            OnboardingFlow(initialProfile: model.profile) { model.completeOnboarding(with: $0) }
        }
        .onChange(of: model.flags.plugFeaturesEnabled) { _, enabled in
            if !enabled, model.selectedTab == .plugs { model.selectedTab = .scan }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in refreshPlugs(for: phase) }
    }

    /// Spec §8.3: re-plan paired plugs whenever the app comes to the foreground, and queue the best-effort
    /// background refresh when it leaves, whether or not the Plugs tab was ever opened.
    private func refreshPlugs(for phase: ScenePhase) {
        guard model.flags.plugFeaturesEnabled else { return }
        switch phase {
        case .active:
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
