import SwiftUI

/// iOS 26 floating glass tab bar: Scan, History, Compare, Plugs (when enabled) and a search-role tab.
struct RootView: View {
    @Environment(AppModel.self) private var model
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
    }
}

#Preview {
    RootView().environment(AppModel.preview())
}
