import SwiftUI
import GreenCore

/// Step 2: Bonjour `_shelly._tcp` discovery, with manual IP entry as the fallback.
struct PlugDiscoveryView: View {
    @Bindable var pairing: PairingModel
    @State private var browser = BonjourBrowser()
    @State private var manualAddress = ""
    @State private var connectingTo: String?

    var body: some View {
        List {
            Section {
                if browser.services.isEmpty {
                    HStack(spacing: 12) {
                        if case .searching = browser.state { ProgressView() }
                        Text(statusText).foregroundStyle(.secondary)
                    }
                }
                ForEach(browser.services) { service in
                    Button {
                        connect(label: service.name) { await BonjourBrowser.resolve(service) }
                    } label: {
                        HStack {
                            Label(service.name, systemImage: "powerplug")
                            Spacer()
                            if connectingTo == service.name { ProgressView() }
                        }
                    }
                    .disabled(pairing.isVerifying)
                }
            } header: {
                Text("On this network")
            }

            #if targetEnvironment(simulator)
            Section {
                ForEach(SimulatedPlugs.all) { dummy in
                    Button {
                        connect(label: dummy.name) { dummy.endpoint }
                    } label: {
                        HStack {
                            Label(dummy.name, systemImage: "powerplug")
                            Spacer()
                            Text("\(Int(dummy.loadWatts)) W").font(.caption).foregroundStyle(.secondary)
                            if connectingTo == dummy.name { ProgressView() }
                        }
                    }
                    .disabled(pairing.isVerifying)
                    .accessibilityIdentifier("pairing.simulated.\(dummy.host)")
                }
            } header: {
                Text("Simulator plugs")
            } footer: {
                Text("Dummy Shelly plugs that only exist in the Simulator. They draw their load while on and follow the schedule.")
            }
            #endif

            Section {
                TextField("192.168.1.42", text: $manualAddress)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(connectManually)
                Button("Connect", systemImage: "link", action: connectManually)
                    .disabled(manualEndpoint == nil || pairing.isVerifying)
            } header: {
                Text("Enter IP address")
            } footer: {
                Text("Find the IP in the Shelly app under Settings → Device information.")
            }

            if let message = pairing.errorMessage {
                Section { PairingErrorText(message: message) }
            }
        }
        .navigationTitle("Find your plug")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }

    private var statusText: String {
        switch browser.state {
        case .searching: "Looking for Shelly plugs…"
        case .failed(let message): "Discovery unavailable: \(message)"
        case .idle: "Not searching."
        }
    }

    /// Parses "host" or "host:port".
    private var manualEndpoint: PlugEndpoint? {
        let trimmed = manualAddress.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let port = Int(parts[1]) { return PlugEndpoint(host: String(parts[0]), port: port) }
        return parts.count == 1 ? PlugEndpoint(host: trimmed) : nil
    }

    private func connectManually() {
        guard let endpoint = manualEndpoint else { return }
        connect(label: endpoint.host) { endpoint }
    }

    private func connect(label: String, endpoint: @escaping () async -> PlugEndpoint) {
        connectingTo = label
        Task {
            await pairing.verify(await endpoint())
            connectingTo = nil
        }
    }
}
