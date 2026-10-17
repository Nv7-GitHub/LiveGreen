import BackgroundTasks
import Foundation

/// Best-effort `BGAppRefreshTask` that re-plans green-hours schedules on paired plugs (spec §8.3).
/// The plug keeps running its last schedule regardless; this only refreshes the plan.
///
/// Call `BackgroundRefresh.register(model:)` from `LiveGreenApp.init` (before launch finishes).
/// Until it is registered, `schedule()` does nothing, since submitting an unregistered task traps.
enum BackgroundRefresh {
    static let taskIdentifier = "com.nv7.LiveGreen.plugrefresh"
    /// How long to wait before asking the system for the next refresh.
    static let interval: TimeInterval = 6 * 3600

    private(set) static var isRegistered = false

    /// Registers the launch handler. Must run before the app finishes launching.
    static func register(model: AppModel) {
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            let task = UncheckedTask(task: task)
            MainActor.assumeIsolated {
                let work = Task { @MainActor in
                    await run(model: model)
                    task.task.setTaskCompleted(success: !Task.isCancelled)
                }
                task.task.expirationHandler = { work.cancel() }
            }
        }
    }

    /// Asks the system for the next refresh. Fails quietly where background refresh is unavailable
    /// (Simulator, Low Power Mode, user disabled) or the handler isn't registered.
    static func schedule(after interval: TimeInterval = interval) {
        guard isRegistered else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs one refresh: re-plan every scheduled plug, then queue the next refresh.
    static func run(model: AppModel, center: PlugCenter = .shared) async {
        defer { schedule() }
        guard model.flags.plugFeaturesEnabled else { return }
        await center.replanAll(services: model.services, profile: model.profile)
    }
}

/// BGTask isn't Sendable; the handler runs on the main queue and only touches it there.
private struct UncheckedTask: @unchecked Sendable {
    let task: BGTask
}
