import Foundation

/// A simulated Shelly plug for demos (spec §8.2 step 6). It draws `loadWatts` (with a little ripple)
/// while on, accumulates energy over wall-clock time, and stores schedule jobs in memory and follows
/// them exactly as the real plug would: each window start switches on, each end switches off, and a
/// manual override lasts until the next scheduled boundary.
public actor MockPlugController: PlugController {
    public let loadWatts: Double
    public private(set) var jobs: [ShellyScheduleJob] = []
    public private(set) var schedule: PlugSchedule?
    private var isOn: Bool
    private var energyWh: Double = 0
    private var lastUpdate: Date
    private let clock: @Sendable () -> Date

    public init(loadWatts: Double = 170, isOn: Bool = false, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.loadWatts = loadWatts
        self.isOn = isOn
        self.clock = clock
        self.lastUpdate = clock()
    }

    public func deviceInfo() async throws -> PlugDeviceInfo {
        PlugDeviceInfo(id: "shellyplugus-demo", model: "SNPL-00116US", generation: 2, firmware: "1.4.4 (simulated)",
                       name: "Demo plug", authEnabled: false)
    }

    public func status() async throws -> PlugStatus {
        let now = clock()
        advance(to: now)
        return PlugStatus(isOn: isOn, activePowerW: isOn ? instantaneousWatts(at: now) : 0, totalEnergyWh: energyWh,
                          temperatureC: isOn ? 38 : 29, timestamp: now)
    }

    public func setSwitch(on: Bool) async throws {
        advance(to: clock())
        isOn = on
    }

    public func replaceSchedule(_ schedule: PlugSchedule) async throws {
        let now = clock()
        advance(to: now)
        self.schedule = schedule
        jobs = ShellySchedulePlan.jobs(for: schedule)
        isOn = ShellySchedulePlan.isOn(schedule, atHour: calendar(for: schedule).component(.hour, from: now))
    }

    /// Integrates energy up to `date`, applying schedule jobs at each hour boundary crossed.
    private func advance(to date: Date) {
        guard date > lastUpdate else { return }
        var cursor = lastUpdate
        if let schedule {
            let calendar = calendar(for: schedule)
            while let boundary = calendar.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0),
                                                   matchingPolicy: .nextTime), boundary <= date {
                accumulate(from: cursor, to: boundary)
                applyJobs(atHour: calendar.component(.hour, from: boundary))
                cursor = boundary
            }
        }
        accumulate(from: cursor, to: date)
        lastUpdate = date
    }

    private func accumulate(from start: Date, to end: Date) {
        if isOn { energyWh += loadWatts * end.timeIntervalSince(start) / 3600 }
    }

    private func applyJobs(atHour hour: Int) {
        for job in jobs where job.enable && Self.hours(in: job.timespec).contains(hour) {
            if let on = job.switchOn { isOn = on }
        }
    }

    /// Hour field of a "sec min hour * * *" timespec.
    static func hours(in timespec: String) -> Set<Int> {
        let fields = timespec.split(separator: " ")
        guard fields.count >= 3 else { return [] }
        return Set(fields[2].split(separator: ",").compactMap { Int($0) })
    }

    /// A small ripple so the dashboard reading looks live.
    private func instantaneousWatts(at date: Date) -> Double {
        loadWatts * (1 + 0.02 * sin(date.timeIntervalSinceReferenceDate / 7))
    }

    private func calendar(for schedule: PlugSchedule) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
        return calendar
    }
}
