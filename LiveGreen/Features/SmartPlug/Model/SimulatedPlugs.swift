#if targetEnvironment(simulator)
import Foundation
import Synchronization
import GreenCore

/// Dummy Shelly plugs for the iOS Simulator, which has no Shelly on its network. They show up in pairing next to
/// Bonjour results and pair through the same flow; `PlugConnector.live` hands back a `SimulatedShellyPlug` for
/// their hosts. Compiled into simulator builds only, so a phone build never shows them.
nonisolated enum SimulatedPlugs {
    struct Dummy: Identifiable, Hashable, Sendable {
        var name: String
        var host: String
        var model: String
        /// What the plugged-in load draws while on, W.
        var loadWatts: Double

        var id: String { host }
        var endpoint: PlugEndpoint { PlugEndpoint(host: host, port: 80, serviceName: name) }
    }

    static let all = [
        Dummy(name: "shellyplugus-ebike", host: "shelly-ebike.sim", model: "SNPL-00116US", loadWatts: 170),
        Dummy(name: "shellyplugus-laptop", host: "shelly-laptop.sim", model: "SNPL-00116US", loadWatts: 65),
        Dummy(name: "shellyplugus-phone", host: "shelly-phone.sim", model: "SNPL-00116US", loadWatts: 18),
    ]

    /// One controller per dummy, shared for the app's life so on/off, energy and the schedule carry across screens.
    private static let controllers = Mutex<[String: SimulatedShellyPlug]>([:])

    static func controller(for endpoint: PlugEndpoint) -> SimulatedShellyPlug? {
        guard let dummy = all.first(where: { $0.host == endpoint.host }) else { return nil }
        return controllers.withLock { live in
            if let existing = live[dummy.host] { return existing }
            let plug = SimulatedShellyPlug(dummy: dummy)
            live[dummy.host] = plug
            return plug
        }
    }
}

/// A Shelly Gen2 plug in memory. It draws its load (with a little ripple) while on, adds up energy over wall-clock
/// time, and follows a written schedule as the real plug would: on at each window start, off at each end, and a
/// manual switch lasts until the next boundary. Energy starts from zero each launch, like a plug after a reboot.
actor SimulatedShellyPlug: PlugController {
    let dummy: SimulatedPlugs.Dummy
    private var isOn = false
    private var energyWh: Double = 0
    private var lastUpdate = Date()
    private var schedule: PlugSchedule?

    init(dummy: SimulatedPlugs.Dummy) {
        self.dummy = dummy
    }

    func deviceInfo() async throws -> PlugDeviceInfo {
        PlugDeviceInfo(id: dummy.name, model: dummy.model, generation: 2, firmware: "1.4.4 (simulated)",
                       name: nil, authEnabled: false)
    }

    func status() async throws -> PlugStatus {
        let now = Date()
        advance(to: now)
        let ripple = 1 + 0.02 * sin(now.timeIntervalSinceReferenceDate / 7)
        return PlugStatus(isOn: isOn, activePowerW: isOn ? dummy.loadWatts * ripple : 0, totalEnergyWh: energyWh,
                          temperatureC: isOn ? 38 : 29, timestamp: now)
    }

    func setSwitch(on: Bool) async throws {
        advance(to: Date())
        isOn = on
    }

    func replaceSchedule(_ schedule: PlugSchedule) async throws {
        let now = Date()
        advance(to: now)
        self.schedule = schedule
        isOn = ShellySchedulePlan.isOn(schedule, atHour: calendar(for: schedule).component(.hour, from: now))
    }

    /// Adds energy up to `date`, switching at each hour boundary the schedule crosses.
    private func advance(to date: Date) {
        guard date > lastUpdate else { return }
        var cursor = lastUpdate
        if let schedule {
            let calendar = calendar(for: schedule)
            while let boundary = calendar.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0),
                                                   matchingPolicy: .nextTime), boundary <= date {
                accumulate(from: cursor, to: boundary)
                isOn = ShellySchedulePlan.isOn(schedule, atHour: calendar.component(.hour, from: boundary))
                cursor = boundary
            }
        }
        accumulate(from: cursor, to: date)
        lastUpdate = date
    }

    private func accumulate(from start: Date, to end: Date) {
        if isOn { energyWh += dummy.loadWatts * end.timeIntervalSince(start) / 3600 }
    }

    private func calendar(for schedule: PlugSchedule) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
        return calendar
    }
}
#endif
