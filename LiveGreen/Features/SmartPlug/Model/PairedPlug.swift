import Foundation
import GreenCore

/// A plug the user paired (spec §8.2), persisted as JSON in UserDefaults.
nonisolated struct PairedPlug: Codable, Identifiable, Hashable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        /// A Shelly Gen2+ plug reached over its local RPC API.
        case shelly(PlugEndpoint)
        /// The simulated plug used for demos.
        case mock
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var device: PlugDeviceInfo
    /// The scanned component this plug powers, if assigned.
    var componentID: UUID?
    var componentName: String?
    var candidate: PlugCandidate?
    /// Charging hours to schedule per day.
    var requiredHours: Double = 3
    /// Local hour (0–23) by which charging must be done.
    var deadlineHour = 7
    /// The plan last written to the plug.
    var schedule: PlugSchedule?
    var scheduleAppliedAt: Date?
    var savings = PlugSavingsLedger()
    /// First failed poll since the last success; nil while reachable.
    var offlineSince: Date?

    var isMock: Bool { kind == .mock }

    /// Keychain account holding the device password, if any.
    var passwordAccount: String { "shelly-\(id.uuidString)" }

    var hostDescription: String {
        switch kind {
        case .shelly(let endpoint): endpoint.port == 80 ? endpoint.host : "\(endpoint.host):\(endpoint.port)"
        case .mock: "Simulated"
        }
    }
}

/// Cumulative measured savings: aenergy deltas × (baseline − actual hourly intensity).
nonisolated struct PlugSavingsLedger: Codable, Hashable, Sendable {
    var savedKgCO2e: Double = 0
    var measuredKWh: Double = 0
    var lastEnergyWh: Double?
    var lastSampleDate: Date?

    /// Folds in a new `aenergy.total` reading taken while the grid was at `intensity` g/kWh,
    /// compared against the day's average `baseline`.
    mutating func record(totalEnergyWh: Double, at date: Date, intensity: Double, baseline: Double) {
        defer {
            lastEnergyWh = totalEnergyWh
            lastSampleDate = date
        }
        guard let last = lastEnergyWh else { return }
        // The counter resets on reboot; count the new total from zero.
        let deltaWh = totalEnergyWh >= last ? totalEnergyWh - last : totalEnergyWh
        guard deltaWh > 0 else { return }
        let kWh = deltaWh / 1000
        measuredKWh += kWh
        savedKgCO2e += kWh * (baseline - intensity) / 1000
    }
}
