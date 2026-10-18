import SwiftUI
import GreenCore

/// One plug: live status, grid now, today's green hours, schedule controls and measured savings (spec §8.3).
struct PlugDashboard: View {
    /// Read in `body` so converted numbers refresh when Settings switches units.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
    let plugID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var dashboard: PlugDashboardModel
    @State private var confirmsForget = false

    init(plugID: UUID) {
        self.plugID = plugID
        _dashboard = State(initialValue: PlugDashboardModel(plugID: plugID))
    }

    var body: some View {
        let _ = unitSystem
        ScrollView {
            if let plug = dashboard.plug {
                VStack(spacing: 16) {
                    PlugStatusCard(plug: plug, status: dashboard.status, isSwitching: dashboard.isSwitching,
                                   onToggle: { on in Task { await dashboard.setSwitch(on: on) } })
                    gridCard
                    PlugScheduleCard(plug: plug, dashboard: dashboard, components: model.plugCandidateComponents)
                    PlugSavingsCard(plug: plug, outlook: dashboard.outlook)
                }
                .padding()
            }
        }
        .navigationTitle(dashboard.plug?.name ?? "Plug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Forget plug", systemImage: "trash", role: .destructive) { confirmsForget = true }
                }
            }
        }
        .confirmationDialog("Forget this plug?", isPresented: $confirmsForget, titleVisibility: .visible) {
            Button("Forget plug", role: .destructive, action: forget)
        } message: {
            Text("Its schedule stays on the plug until you change it in the Shelly app.")
        }
        .task { await dashboard.loadOutlook(services: model.services, profile: model.profile) }
        .task(id: plugID) { await dashboard.pollStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await dashboard.loadOutlook(services: model.services, profile: model.profile) }
        }
        .alert("Smart plug", isPresented: Binding(get: { dashboard.message != nil }, set: { if !$0 { dashboard.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dashboard.message ?? "")
        }
    }

    @ViewBuilder
    private var gridCard: some View {
        if let outlook = dashboard.outlook {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill").font(.title2).foregroundStyle(Theme.leaf)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grid now").font(.caption).foregroundStyle(.secondary)
                    Text(DisplayUnits.gridIntensity(gramsPerKWh: outlook.intensity()))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(outlook.current?.isEstimated == false ? "Live · \(outlook.zone)" : "Estimated · \(outlook.zone)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let issue = outlook.historyIssue {
                        Label("Grid history unavailable (\(issue)); planning from stored readings or the regional pattern.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(Theme.warning)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Day average").font(.caption).foregroundStyle(.secondary)
                    Text(Measured.format(DisplayUnits.gridIntensityValue(gramsPerKWh: outlook.forecast.dayAverage))).font(.headline.monospacedDigit())
                }
            }
            .glassCard()
        } else if dashboard.gridUnavailable {
            Label("Grid intensity is unavailable right now. Scheduling needs it, so try again shortly.",
                  systemImage: "exclamationmark.icloud")
                .font(.subheadline)
                .glassCard()
        } else {
            ProgressView("Loading grid forecast…").frame(maxWidth: .infinity).glassCard()
        }
    }

    private func forget() {
        PlugCenter.shared.remove(id: plugID)
        dismiss()
    }
}

#Preview {
    NavigationStack { PlugDashboard(plugID: UUID()) }.environment(AppModel.preview())
}
