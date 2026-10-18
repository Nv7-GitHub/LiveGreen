import Foundation
import Observation
import GreenCore

/// Paired plugs, their controllers and schedule writes. Shared by the Plugs tab, pairing and
/// background refresh.
@Observable
final class PlugCenter {
    static let shared = PlugCenter(defaults: LaunchArguments().inMemoryStore ? .throwaway : .standard)

    private(set) var plugs: [PairedPlug] = []
    @ObservationIgnored let connector: PlugConnector
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    static let defaultsKey = "LiveGreen.pairedPlugs"
    static let keychainService = "com.nv7.LiveGreen.shelly"

    init(connector: PlugConnector = .live, defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.connector = connector
        self.defaults = defaults
        self.calendar = calendar
        plugs = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([StoredPlug].self, from: $0) }?
            .compactMap(\.plug) ?? []
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

    /// Forgets every plug and its stored password. Schedules already on the plugs keep running.
    func removeAll() {
        for plug in plugs { Keychain.delete(account: plug.passwordAccount, service: Self.keychainService) }
        plugs = []
        persist()
    }

    func controller(for plug: PairedPlug) -> any PlugController {
        connector.controller(for: plug.kind,
                             password: Keychain.read(account: plug.passwordAccount, service: Self.keychainService))
    }

    // MARK: - Scheduling

    func plan(for plug: PairedPlug, outlook: GridOutlook, now: Date = Date()) -> PlugSchedule {
        outlook.schedule(requiredHours: plug.requiredHours, deadlineHour: plug.deadlineHour, now: now, calendar: calendar)
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

    // MARK: - Status

    /// Records a successful poll: clears the offline flag and accrues measured savings.
    func record(_ status: PlugStatus, for plugID: UUID, outlook: GridOutlook?) {
        guard var plug = plug(id: plugID) else { return }
        plug.offlineSince = nil
        if let outlook {
            plug.savings.record(totalEnergyWh: status.totalEnergyWh, at: status.timestamp,
                                intensity: outlook.intensity(at: status.timestamp, calendar: calendar),
                                baseline: outlook.forecast.dayAverage)
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

/// One saved plug, or nil when it no longer decodes (such as a plug of a kind since removed), so one stale
/// entry doesn't drop every paired plug.
private struct StoredPlug: Decodable {
    let plug: PairedPlug?

    init(from decoder: any Decoder) throws {
        plug = try? PairedPlug(from: decoder)
    }
}

private extension UserDefaults {
    /// Paired plugs for a throwaway session (`-InMemoryStore YES`, used by UI tests), cleared at launch.
    static var throwaway: UserDefaults {
        let name = "com.nv7.LiveGreen.throwaway"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
