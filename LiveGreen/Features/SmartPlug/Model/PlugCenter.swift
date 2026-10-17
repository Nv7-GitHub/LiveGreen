import Foundation
import Observation
import GreenCore

/// Paired plugs, their controllers and schedule writes. Shared by the Plugs tab, pairing and
/// background refresh.
@Observable
final class PlugCenter {
    static let shared = PlugCenter()

    private(set) var plugs: [PairedPlug] = []
    @ObservationIgnored let connector: PlugConnector
    @ObservationIgnored let planner: any GreenHoursPlanning
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    static let defaultsKey = "LiveGreen.pairedPlugs"
    static let keychainService = "com.nv7.LiveGreen.shelly"

    init(connector: PlugConnector = .live, planner: any GreenHoursPlanning = LocalGreenHoursPlanner(),
         defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.connector = connector
        self.planner = planner
        self.defaults = defaults
        self.calendar = calendar
        plugs = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([PairedPlug].self, from: $0) } ?? []
    }

    func plug(id: UUID) -> PairedPlug? { plugs.first { $0.id == id } }

    // MARK: - Pairing

    func add(_ plug: PairedPlug, password: String?) {
        if let password, !password.isEmpty {
            try? Keychain.write(password, account: plug.passwordAccount, service: Self.keychainService)
        }
        plugs.append(plug)
        persist()
    }

    func update(_ plug: PairedPlug) {
        guard let index = plugs.firstIndex(where: { $0.id == plug.id }) else { return }
        plugs[index] = plug
        persist()
    }

    func remove(id: UUID) {
        guard let plug = plug(id: id) else { return }
        Keychain.delete(account: plug.passwordAccount, service: Self.keychainService)
        plugs.removeAll { $0.id == id }
        persist()
    }

    /// Pairs the simulated plug when the Settings "Mock plug" toggle is on and none exists yet.
    func ensureMockPlug(enabled: Bool) async {
        guard enabled, !plugs.contains(where: \.isMock),
              let info = try? await connector.mock.deviceInfo() else { return }
        add(PairedPlug(name: info.name ?? "Mock plug", kind: .mock, device: info), password: nil)
    }

    func controller(for plug: PairedPlug) -> any PlugController {
        connector.controller(for: plug.kind,
                             password: Keychain.read(account: plug.passwordAccount, service: Self.keychainService))
    }

    // MARK: - Scheduling

    func plan(for plug: PairedPlug, outlook: GridOutlook, now: Date = Date()) -> PlugSchedule {
        planner.plan(forecast: outlook.forecast, requiredHours: plug.requiredHours,
                     deadlineHour: plug.deadlineHour, now: now, calendar: calendar)
    }

    /// Writes the current plan to the plug (the plug enforces it while the app is closed) and
    /// switches it to match the current hour.
    @discardableResult
    func applySchedule(to plugID: UUID, outlook: GridOutlook, now: Date = Date()) async throws -> PlugSchedule {
        guard let plug = plug(id: plugID) else { throw GreenCoreError.notFound }
        let schedule = plan(for: plug, outlook: outlook, now: now)
        let controller = controller(for: plug)
        try await controller.replaceSchedule(schedule)
        try await controller.setSwitch(on: schedule.onHours.contains(calendar.component(.hour, from: now)))
        guard var updated = self.plug(id: plugID) else { return schedule }
        updated.schedule = schedule
        updated.scheduleAppliedAt = now
        updated.offlineSince = nil
        update(updated)
        return schedule
    }

    /// Re-plans every plug that already has a schedule (foreground and background refresh).
    func replanAll(services: ServiceContainer, profile: UserProfile) async {
        let scheduled = plugs.filter { $0.schedule != nil }
        guard !scheduled.isEmpty,
              let outlook = try? await GridOutlook.load(grid: services.grid, reference: services.reference, profile: profile)
        else { return }
        for plug in scheduled {
            do {
                try await applySchedule(to: plug.id, outlook: outlook)
            } catch {
                markOffline(plug.id)
            }
        }
    }

    /// The simulated plug doesn't run schedules itself, so follow the plan when the hour changes.
    func enforceMockSchedule(for plug: PairedPlug, lastHour: Int?, now: Date = Date()) async -> Int {
        let hour = calendar.component(.hour, from: now)
        if plug.isMock, let schedule = plug.schedule, let lastHour, lastHour != hour {
            try? await connector.mock.setSwitch(on: schedule.onHours.contains(hour))
        }
        return hour
    }

    // MARK: - Status

    /// Records a successful poll: clears the offline flag and accrues measured savings.
    func record(_ status: PlugStatus, for plugID: UUID, outlook: GridOutlook?) {
        guard var plug = plug(id: plugID) else { return }
        plug.offlineSince = nil
        if let outlook {
            plug.savings.record(totalEnergyWh: status.totalEnergyWh, at: status.timestamp,
                                intensity: outlook.intensity(at: status.timestamp, calendar: calendar),
                                baseline: outlook.forecast.average)
        } else {
            plug.savings.lastEnergyWh = status.totalEnergyWh
            plug.savings.lastSampleDate = status.timestamp
        }
        update(plug)
    }

    func markOffline(_ plugID: UUID, at date: Date = Date()) {
        guard var plug = plug(id: plugID), plug.offlineSince == nil else { return }
        plug.offlineSince = date
        update(plug)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(plugs) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
