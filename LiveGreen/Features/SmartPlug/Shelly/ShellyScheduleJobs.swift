import Foundation
import GreenCore

/// One `Schedule.Create` job: at `hour`:00 every day, switch output 0 on or off.
nonisolated struct ShellyScheduleJob: Hashable, Sendable {
    var hour: Int
    var turnOn: Bool

    /// Shelly cron timespec: "sec min hour dom month dow".
    var timespec: String { "0 0 \(hour) * * *" }

    var createParams: [String: Any] {
        ["enable": true,
         "timespec": timespec,
         "calls": [["method": "Switch.Set", "params": ["id": 0, "on": turnOn]]]]
    }

    /// On/off jobs for each window of a daily plan. A window ending at midnight that continues
    /// into one starting at midnight is treated as a single overnight window.
    static func jobs(for schedule: PlugSchedule) -> [ShellyScheduleJob] {
        var windows = schedule.windows
        if windows.count > 1, let first = windows.first, let last = windows.last,
           first.lowerBound == 0, last.upperBound == 24 {
            windows.removeFirst()
            windows[windows.count - 1] = last.lowerBound..<(24 + first.upperBound)
        }
        // A plan covering all 24 hours just stays on.
        if windows.count == 1, windows[0].count >= 24 { return [ShellyScheduleJob(hour: windows[0].lowerBound % 24, turnOn: true)] }
        return windows.flatMap { window in
            [ShellyScheduleJob(hour: window.lowerBound % 24, turnOn: true),
             ShellyScheduleJob(hour: window.upperBound % 24, turnOn: false)]
        }
    }
}
