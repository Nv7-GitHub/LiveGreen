import Foundation
import GreenCore

/// Builds controllers for paired plugs. `makeShelly` is the single binding point for the live client.
nonisolated struct PlugConnector: Sendable {
    var makeShelly: @Sendable (PlugEndpoint, _ password: String?) -> any PlugController

    static let live = PlugConnector(
        makeShelly: { endpoint, password in
            #if targetEnvironment(simulator)
            if let simulated = SimulatedPlugs.controller(for: endpoint) { return simulated }
            #endif
            return ShellyClient(endpoint: endpoint, password: password)
        })

    func controller(for kind: PairedPlug.Kind, password: String?) -> any PlugController {
        switch kind {
        case .shelly(let endpoint): makeShelly(endpoint, password)
        }
    }
}
