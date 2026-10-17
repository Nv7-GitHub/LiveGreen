import Foundation
import GreenCore

/// Simulated plug: draws `loadWatts` while on and accumulates energy over wall-clock time.
public actor FakePlugController: PlugController {
    public let loadWatts: Double
    private var isOn: Bool
    private var energyWh: Double = 0
    private var lastUpdate: Date
    public private(set) var schedule: PlugSchedule?

    public init(loadWatts: Double = 170, isOn: Bool = false, now: Date = Date()) {
        self.loadWatts = loadWatts
        self.isOn = isOn
        self.lastUpdate = now
    }

    public func deviceInfo() async throws -> PlugDeviceInfo {
        PlugDeviceInfo(id: "shellyplugus-mock", model: "SNPL-00116US", generation: 2, firmware: "1.4.4-mock", name: "Mock plug")
    }

    public func status() async throws -> PlugStatus {
        accumulate()
        return PlugStatus(isOn: isOn, activePowerW: isOn ? loadWatts : 0, totalEnergyWh: energyWh,
                          temperatureC: 31, timestamp: lastUpdate)
    }

    public func setSwitch(on: Bool) async throws {
        accumulate()
        isOn = on
    }

    public func replaceSchedule(_ schedule: PlugSchedule) async throws {
        self.schedule = schedule
    }

    private func accumulate() {
        let now = Date()
        if isOn { energyWh += loadWatts * now.timeIntervalSince(lastUpdate) / 3600 }
        lastUpdate = now
    }
}
