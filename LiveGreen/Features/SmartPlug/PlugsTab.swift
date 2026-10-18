import SwiftUI
import GreenCore

/// Smart plug home (spec §8): paired plugs, pairing entry point and plug recommendations from scans.
struct PlugsTab: View {
    /// Read in `body` so converted numbers refresh when Settings switches units.
    @AppStorage(DisplayUnits.defaultsKey) private var unitSystem: UnitSystem = .imperial
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var showsPairing = false
    private let center = PlugCenter.shared

    /// Scanned loads that don't have a plug assigned yet.
    private var recommendations: [Component] {
        let assigned = Set(center.plugs.compactMap(\.componentName).map { $0.lowercased() })
        return model.plugCandidateComponents.filter { !assigned.contains($0.name.lowercased()) }
    }

    var body: some View {
        let _ = unitSystem
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if center.plugs.isEmpty {
                        emptyState
                    } else {
                        GlassEffectContainer(spacing: 12) {
                            VStack(spacing: 12) {
                                ForEach(center.plugs) { plug in
                                    NavigationLink(value: plug.id) { PlugRow(plug: plug) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        Button {
                            showsPairing = true
                        } label: {
                            Label("Pair another plug", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }

                    if !recommendations.isEmpty {
                        Text("Recommended from your scans").font(.title3.weight(.semibold)).padding(.top, 8)
                        ForEach(recommendations) { component in
                            if let candidate = component.plugCandidate {
                                PlugRecommendationCard(component: component, candidate: candidate)
                            }
                        }
                    }
                }
                .padding()
            }
            .greeneryBackground(.plugs)
            .navigationTitle("Plugs")
            .navigationDestination(for: UUID.self) { id in
                PlugDashboard(plugID: id)
            }
            .settingsToolbarButton()
            .sheet(isPresented: $showsPairing) {
                PairingFlow { plug in path = [plug.id] }
            }
        }
    }

    private var emptyState: some View {
        GreeneryEmptyState(art: .sproutingPlug, title: "Charge when the grid is clean", caption: "Green hours, every day",
                           message: "Pair a Shelly smart plug and LiveGreen writes a daily schedule to it, so your chargers run in the cleanest hours, even with the app closed.") {
            Button {
                showsPairing = true
            } label: {
                Label("Pair a Shelly plug", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier("plugs.pair")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Summary row for a paired plug.
private struct PlugRow: View {
    let plug: PairedPlug

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "powerplug.fill")
                .font(.title2)
                .foregroundStyle(plug.offlineSince == nil ? Theme.leaf : Theme.warning)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(plug.name).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.cardCornerRadius))
    }

    private var subtitle: String {
        if let offline = plug.offlineSince { return "Offline since \(offline.formatted(date: .omitted, time: .shortened))" }
        if let schedule = plug.schedule { return "Green hours: \(PlugScheduleCard.describe(schedule))" }
        return plug.componentName.map { "Powers \($0) · no schedule yet" } ?? "No schedule yet"
    }
}

#Preview {
    PlugsTab().environment(AppModel.preview())
}
