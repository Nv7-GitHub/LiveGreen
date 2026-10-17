import SwiftUI

/// Step 1: get the plug onto the network, or pick the mock plug.
struct PairingInstructionsView: View {
    @Bindable var pairing: PairingModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LiveGreen talks to Shelly Gen2+ plugs directly on your Wi-Fi and writes a green-hours schedule the plug follows on its own.")
                    .foregroundStyle(.secondary)

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        step(1, "Plug it in", "Plug the Shelly into the outlet that powers your charger.")
                        step(2, "Join your Wi-Fi", "In the Shelly app, add the plug to your home Wi-Fi. A new plug starts in AP mode (a \"ShellyPlug-…\" network) until you do.")
                        step(3, "Stay on the same network", "Keep this phone on that Wi-Fi so LiveGreen can find the plug.")
                    }
                }

                Button {
                    pairing.path.append(.discover)
                } label: {
                    Label("Find my plug", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    Task { await pairing.chooseMock() }
                } label: {
                    Label("Use a mock plug instead", systemImage: "cpu")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(pairing.isVerifying)
                .accessibilityIdentifier("pairing.useMock")

                PairingErrorText(message: pairing.errorMessage)
            }
            .padding()
        }
        .navigationTitle("Pair a plug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(number).circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.leaf)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
