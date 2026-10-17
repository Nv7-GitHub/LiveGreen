import Foundation
import GreenCore

/// Builds controllers for paired plugs. `makeShelly` is the single binding point for the live client.
nonisolated struct PlugConnector: Sendable {
    var makeShelly: @Sendable (PlugEndpoint, _ password: String?) -> any PlugController
    /// Shared so the simulated plug keeps its state (on/off, energy, schedule) across screens.
    let mock: MockPlugController

    static let live = PlugConnector(
        makeShelly: { endpoint, password in ShellyClient(endpoint: endpoint, password: password) },
        mock: MockPlugController(loadWatts: 170))

    func controller(for kind: PairedPlug.Kind, password: String?) -> any PlugController {
        switch kind {
        case .shelly(let endpoint): makeShelly(endpoint, password)
        case .mock: mock
        }
    }
}
