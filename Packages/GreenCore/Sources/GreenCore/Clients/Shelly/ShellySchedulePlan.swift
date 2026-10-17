import Foundation

/// One Shelly `Schedule.Create` job: a 6-field cron timespec ("sec min hour dom month dow") and the RPC
/// calls it runs.
public struct ShellyScheduleJob: Codable, Sendable, Hashable {
    public struct Call: Codable, Sendable, Hashable {
        public var method: String
        public var params: SwitchSetParams
    }

    public struct SwitchSetParams: Codable, Sendable, Hashable {
        public var id: Int
        public var on: Bool
    }

    public var enable: Bool
    public var timespec: String
    public var calls: [Call]

    public init(timespec: String, switchOn: Bool, enable: Bool = true) {
        self.enable = enable
        self.timespec = timespec
        self.calls = [Call(method: "Switch.Set", params: SwitchSetParams(id: 0, on: switchOn))]
    }

    public var switchOn: Bool? { calls.first?.params.on }
}

/// Turns a green-hours plan into plug-side schedule jobs (spec §8.3): one job switches on at the start
/// of every window and one switches off at every window end, using comma lists of hours so a whole day
/// fits in two of the plug's limited job slots.
public enum ShellySchedulePlan {
    public static func jobs(for schedule: PlugSchedule) -> [ShellyScheduleJob] {
        let windows = mergedWindows(schedule.windows)
        guard !windows.isEmpty else { return [] }
        if windows.count == 1, windows[0].end - windows[0].start >= 24 {
            return [ShellyScheduleJob(timespec: timespec(hours: [0]), switchOn: true)]
        }
        let starts = windows.map(\.start).sorted()
        let ends = windows.map { $0.end % 24 }.sorted()
        return [
            ShellyScheduleJob(timespec: timespec(hours: starts), switchOn: true),
            ShellyScheduleJob(timespec: timespec(hours: ends), switchOn: false),
        ]
    }

    /// Whether the plan has the plug on during `hour` (local, 0–23).
    public static func isOn(_ schedule: PlugSchedule, atHour hour: Int) -> Bool {
        schedule.onHours.contains(((hour % 24) + 24) % 24)
    }

    /// "0 0 1,13 * * *": second 0, minute 0, at the listed hours, every day.
    static func timespec(hours: [Int]) -> String {
        "0 0 \(hours.map(String.init).joined(separator: ",")) * * *"
    }

    /// Windows as (start, end) hours where `end` may exceed 24 when a window wraps past midnight;
    /// a window ending at 24 is joined with one starting at 0.
    static func mergedWindows(_ windows: [Range<Int>]) -> [(start: Int, end: Int)] {
        var result = windows.map { (start: $0.lowerBound, end: $0.upperBound) }
        if result.count > 1, let first = result.first, let last = result.last, first.start == 0, last.end == 24 {
            result.removeFirst()
            result[result.count - 1].end = 24 + first.end
        }
        return result
    }
}
