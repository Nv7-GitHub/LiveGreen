import SwiftUI
import GreenCore

/// Pair a Shelly plug (spec §8.2). Present as a sheet.
struct PairingFlow: View {
    var preselectedComponentID: UUID?
    var onFinish: (PairedPlug) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var pairing = PairingModel(connector: PlugCenter.shared.connector)

    var body: some View {
        NavigationStack(path: $pairing.path) {
            PairingInstructionsView(pairing: pairing)
                .navigationDestination(for: PairingModel.Step.self) { step in
                    switch step {
                    case .discover:
                        PlugDiscoveryView(pairing: pairing)
                    case .password:
                        PlugPasswordView(pairing: pairing)
                    case .name:
                        PlugNamingView(pairing: pairing, preselectedComponentID: preselectedComponentID) { plug in
                            onFinish(plug)
                            dismiss()
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// Inline error line shared by the pairing steps.
struct PairingErrorText: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PairingFlow().environment(AppModel.preview())
}
