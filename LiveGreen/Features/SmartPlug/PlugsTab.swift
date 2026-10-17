import SwiftUI
import GreenCore

/// Smart plug dashboard and pairing entry point (spec §8).
struct PlugsTab: View {
    @Environment(AppModel.self) private var model
    @State private var status: PlugStatus?

    var body: some View {
        NavigationStack {
            List {
                if let plug = model.services.plug {
                    Section("Plug") {
                        if let status {
                            LabeledContent("State", value: status.isOn ? "On" : "Off")
                            LabeledContent("Power", value: Measured.format(status.activePowerW) + " W")
                        }
                        Button(status?.isOn == true ? "Turn off" : "Turn on") {
                            Task {
                                try? await plug.setSwitch(on: !(status?.isOn ?? false))
                                status = try? await plug.status()
                            }
                        }
                    }
                    .task { status = try? await plug.status() }
                } else {
                    Section {
                        Text("No plug paired. Turn on the mock plug in Settings to try scheduling without hardware.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Recommended") {
                    ForEach(model.scans.flatMap(\.components).filter { $0.plugCandidate != nil }) { component in
                        if let candidate = component.plugCandidate {
                            PlugRecommendationCard(component: component, candidate: candidate) {}
                        }
                    }
                }
            }
            .navigationTitle("Plugs")
            .settingsToolbarButton()
        }
    }
}

#Preview {
    PlugsTab().environment(AppModel.preview())
}
