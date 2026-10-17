import Foundation

/// A Shelly Gen2 schedule job (`Schedule.Create` params).
/// See https://shelly-api-docs.shelly.cloud/gen2/ComponentsAndServices/Schedule
public struct ShellyScheduleJob: Codable, Sendable, Hashable {
    public var enable: Bool
    /// 6-field cron: "second minute hour day-of-month month day-of-week", in the device's local time.
    public var timespec: String
    public var calls: [ShellyCall]

    public init(enable: Bool = true, timespec: String, calls: [ShellyCall]) {
        self.enable = enable
        self.timespec = timespec
        self.calls = calls
    }

    /// A job running a single `Switch.Set` on switch `switchID`.
    public init(timespec: String, switchOn: Bool, switchID: Int = 0, enable: Bool = true) {
        self.init(enable: enable, timespec: timespec,
                  calls: [ShellyCall(method: "Switch.Set", params: SwitchSetParams(id: switchID, on: switchOn))])
    }

    /// The switch state the job sets, when it is a `Switch.Set` job.
    public var switchOn: Bool? { calls.first { $0.method == "Switch.Set" }?.params.on }
}

/// One RPC call inside a schedule job.
public struct ShellyCall: Codable, Sendable, Hashable {
    public var method: String
    public var params: SwitchSetParams

    public init(method: String, params: SwitchSetParams) {
        self.method = method
        self.params = params
    }
}

/// `Switch.Set` parameters.
public struct SwitchSetParams: Codable, Sendable, Hashable {
    public var id: Int
    public var on: Bool

    public init(id: Int, on: Bool) {
        self.id = id
        self.on = on
    }
}

/// A JSON-RPC 2.0 request frame as posted to `http://<ip>/rpc`.
public struct ShellyRPCRequest<Params: Encodable & Sendable>: Encodable, Sendable {
    public var id: Int
    public var method: String
    public var params: Params?
}

/// Turns a `PlugSchedule` into Shelly schedule jobs: one `Switch.Set on` at the start of each on-window
/// and one `Switch.Set off` at its end, repeating daily.
public enum ShellyScheduleBuilder {
    /// Device limit on schedule instances.
    public static let maxJobs = 20
    public static let everyDay = "SUN,MON,TUE,WED,THU,FRI,SAT"

    /// Daily cron at hour:minute, e.g. "0 0 22 * * SUN,MON,TUE,WED,THU,FRI,SAT".
    public static func timespec(hour: Int, minute: Int = 0) -> String {
        "0 \(minute) \(hour) * * \(everyDay)"
    }

    /// On/off transitions in minutes after local midnight, treating the day as circular (a window ending at 24
    /// and one starting at 0 are one window across midnight). Empty schedule → no jobs; all 24 hours → one ON at 0.
    public static func transitions(onHours: [Int]) -> [(minute: Int, on: Bool)] {
        var on = Set(onHours.filter { (0..<24).contains($0) })
        guard !on.isEmpty else { return [] }
        guard on.count < 24 else { return [(0, true)] }
        // Each window needs two jobs; fill the shortest off-gaps until they fit the device limit.
        while windowStarts(on).count * 2 > maxJobs, let gap = shortestGap(on) {
            on.formUnion(gap)
        }
        var result: [(minute: Int, on: Bool)] = []
        for hour in 0..<24 {
            let previousOn = on.contains((hour + 23) % 24)
            if on.contains(hour), !previousOn { result.append((hour * 60, true)) }
            if !on.contains(hour), previousOn { result.append((hour * 60, false)) }
        }
        return result
    }

    /// Jobs for switch `switchID`. When the device runs in another time zone than the schedule, times are shifted
    /// by the offset difference at the schedule's creation date.
    public static func jobs(for schedule: PlugSchedule, switchID: Int = 0, deviceTimeZone: TimeZone? = nil) -> [ShellyScheduleJob] {
        var shift = 0
        if let deviceTimeZone, let scheduleZone = TimeZone(identifier: schedule.timeZoneIdentifier) {
            shift = (deviceTimeZone.secondsFromGMT(for: schedule.createdAt) - scheduleZone.secondsFromGMT(for: schedule.createdAt)) / 60
        }
        return transitions(onHours: schedule.onHours).map { transition in
            let minute = ((transition.minute + shift) % 1440 + 1440) % 1440
            return ShellyScheduleJob(enable: true, timespec: timespec(hour: minute / 60, minute: minute % 60),
                                     calls: [ShellyCall(method: "Switch.Set", params: SwitchSetParams(id: switchID, on: transition.on))])
        }
    }

    /// RPC bodies to replace the plug's schedules: `Schedule.DeleteAll`, then one `Schedule.Create` per job.
    public static func replaceRequests(for schedule: PlugSchedule, switchID: Int = 0, deviceTimeZone: TimeZone? = nil,
                                       firstRequestID: Int = 1) throws -> [Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var bodies = [try encoder.encode(ShellyRPCRequest<SwitchSetParams>(id: firstRequestID, method: "Schedule.DeleteAll", params: nil))]
        for (offset, job) in jobs(for: schedule, switchID: switchID, deviceTimeZone: deviceTimeZone).enumerated() {
            bodies.append(try encoder.encode(ShellyRPCRequest(id: firstRequestID + 1 + offset, method: "Schedule.Create", params: job)))
        }
        return bodies
    }

    private static func windowStarts(_ on: Set<Int>) -> [Int] {
        (0..<24).filter { on.contains($0) && !on.contains(($0 + 23) % 24) }
    }

    /// Hours of the shortest off-run between two on-windows (ties: earliest).
    private static func shortestGap(_ on: Set<Int>) -> [Int]? {
        var best: [Int]?
        for start in 0..<24 where !on.contains(start) && on.contains((start + 23) % 24) {
            var gap: [Int] = []
            var hour = start
            while !on.contains(hour) && gap.count < 24 {
                gap.append(hour)
                hour = (hour + 1) % 24
            }
            if gap.count < (best?.count ?? .max) { best = gap }
        }
        return best
    }
}
