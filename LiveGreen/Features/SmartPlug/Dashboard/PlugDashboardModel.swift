import Foundation
import Observation
import GreenCore

/// Live state for one plug's dashboard: status polling, grid outlook, overrides and schedule writes.
@Observable
final class PlugDashboardModel {
    let plugID: UUID
    private(set) var status: PlugStatus?
    private(set) var outlook: GridOutlook?
    private(set) var gridUnavailable = false
    private(set) var isApplying = false
    private(set) var isSwitching = false
    var message: String?

    @ObservationIgnored private let center: PlugCenter
    @ObservationIgnored private var lastHour: Int?

    static let pollInterval: Duration = .seconds(5)

    init(plugID: UUID, center: PlugCenter = .shared) {
        self.plugID = plugID
        self.center = center
    }

    var plug: PairedPlug? { center.plug(id: plugID) }

    func loadOutlook(services: ServiceContainer, profile: UserProfile) async {
        do {
            outlook = try await GridOutlook.load(grid: services.grid, reference: services.reference, profile: profile)
            gridUnavailable = false
        } catch {
            gridUnavailable = outlook == nil
        }
    }

    /// Polls `Switch.GetStatus` until cancelled; failures mark the plug offline.
    func pollStatus() async {
        while !Task.isCancelled {
            await refreshStatus()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    func refreshStatus() async {
        guard let plug else { return }
        lastHour = await center.enforceMockSchedule(for: plug, lastHour: lastHour)
        do {
            let status = try await center.controller(for: plug).status()
            self.status = status
            center.record(status, for: plugID, outlook: outlook)
        } catch {
            status = nil
            center.markOffline(plugID)
        }
    }

    /// Manual override; the schedule resumes at its next on/off time.
    func setSwitch(on: Bool) async {
        guard let plug else { return }
        isSwitching = true
        defer { isSwitching = false }
        do {
            try await center.controller(for: plug).setSwitch(on: on)
            await refreshStatus()
        } catch {
            message = "Couldn't switch the plug: \(PairingModel.message(for: error))"
            center.markOffline(plugID)
        }
    }

    func applySchedule() async {
        guard let outlook else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let schedule = try await center.applySchedule(to: plugID, outlook: outlook)
            let hours = schedule.onHours.count
            message = "Schedule written: \(hours) green hour\(hours == 1 ? "" : "s") a day. The plug follows it even with the app closed."
            await refreshStatus()
        } catch {
            message = "Couldn't write the schedule: \(PairingModel.message(for: error))"
            center.markOffline(plugID)
        }
    }

    /// The plan for the current settings, previewed before it's applied.
    var previewSchedule: PlugSchedule? {
        guard let plug, let outlook else { return nil }
        return center.plan(for: plug, outlook: outlook)
    }

    func update(_ change: (inout PairedPlug) -> Void) {
        guard var plug else { return }
        change(&plug)
        center.update(plug)
    }
}
