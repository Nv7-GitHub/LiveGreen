import SwiftUI

/// Step 4: the plug has auth enabled, so ask for its password (HTTP digest auth).
struct PlugPasswordView: View {
    @Bindable var pairing: PairingModel

    var body: some View {
        Form {
            Section {
                SecureField("Device password", text: $pairing.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(submit)
            } header: {
                Text(pairing.device?.name ?? pairing.device?.id ?? "Shelly plug")
            } footer: {
                Text("This plug is password-protected. LiveGreen stores the password in your Keychain.")
            }
            Section {
                Button(action: submit) {
                    HStack {
                        Text("Continue")
                        if pairing.isVerifying { Spacer(); ProgressView() }
                    }
                }
                .disabled(pairing.password.isEmpty || pairing.isVerifying)
                PairingErrorText(message: pairing.errorMessage)
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        guard !pairing.password.isEmpty else { return }
        Task { await pairing.verifyPassword() }
    }
}
