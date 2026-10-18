import Foundation
import Observation
import GreenCore

/// State machine for pairing (spec §8.2): discover/enter → verify → optional password → name.
@Observable
final class PairingModel {
    enum Step: Hashable {
        case discover, password, name
    }

    var path: [Step] = []
    private(set) var isVerifying = false
    var errorMessage: String?
    private(set) var kind: PairedPlug.Kind?
    private(set) var device: PlugDeviceInfo?
    var password = ""

    @ObservationIgnored let connector: PlugConnector

    init(connector: PlugConnector) {
        self.connector = connector
    }

    /// Step 3: `Shelly.GetDeviceInfo` (Gen2+ only), then either ask for the password or move on.
    func verify(_ endpoint: PlugEndpoint) async {
        await run {
            let controller = connector.makeShelly(endpoint, nil)
            let info = try await controller.deviceInfo()
            guard info.generation >= 2 else { throw GreenCoreError.unsupported("Shelly Gen1 devices are not supported.") }
            kind = .shelly(endpoint)
            device = info
            password = ""
            path.append(info.authEnabled ? .password : .name)
        }
    }

    /// Step 4: confirms the password with an authenticated `Switch.GetStatus`.
    func verifyPassword() async {
        guard case .shelly(let endpoint) = kind else { return }
        await run {
            _ = try await connector.makeShelly(endpoint, password).status()
            path.append(.name)
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isVerifying = true
        errorMessage = nil
        defer { isVerifying = false }
        do {
            try await work()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        switch error {
        case GreenCoreError.unsupported(let reason): reason
        case GreenCoreError.http(status: 401, _): "That password didn't work. Use the password set in the Shelly app."
        case GreenCoreError.http(let status, _): "The plug answered with an error (HTTP \(status))."
        case GreenCoreError.timeout: "The plug didn't answer in time. Check it's on the same Wi-Fi as this phone."
        case GreenCoreError.notFound: "No Shelly plug answered at that address."
        case is URLError: "Couldn't reach a plug at that address. Check the IP and that you're on the same Wi-Fi."
        default: error.localizedDescription
        }
    }
}
