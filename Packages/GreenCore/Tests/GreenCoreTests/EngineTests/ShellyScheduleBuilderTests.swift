import Foundation
import Testing
@testable import GreenCore

@Suite("Shelly schedule builder")
struct ShellyScheduleBuilderTests {
    let created = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func timespecFormat() {
        #expect(ShellyScheduleBuilder.timespec(hour: 9, minute: 3) == "0 3 9 * * SUN,MON,TUE,WED,THU,FRI,SAT")
        #expect(ShellyScheduleBuilder.timespec(hour: 22) == "0 0 22 * * SUN,MON,TUE,WED,THU,FRI,SAT")
    }

    @Test func onAndOffJobPerWindow() {
        let schedule = PlugSchedule(onHours: [1, 2, 3, 13, 14], timeZoneIdentifier: "America/New_York", createdAt: created)
        let jobs = ShellyScheduleBuilder.jobs(for: schedule)
        #expect(jobs.map(\.timespec) == ["0 0 1 * * SUN,MON,TUE,WED,THU,FRI,SAT", "0 0 4 * * SUN,MON,TUE,WED,THU,FRI,SAT",
                                         "0 0 13 * * SUN,MON,TUE,WED,THU,FRI,SAT", "0 0 15 * * SUN,MON,TUE,WED,THU,FRI,SAT"])
        #expect(jobs.map { $0.calls[0].params.on } == [true, false, true, false])
        #expect(jobs.allSatisfy { $0.enable && $0.calls.count == 1 && $0.calls[0].method == "Switch.Set" && $0.calls[0].params.id == 0 })
    }

    @Test func windowAcrossMidnightIsOneWindow() {
        let transitions = ShellyScheduleBuilder.transitions(onHours: [22, 23, 0, 1])
        #expect(transitions.map(\.minute) == [120, 1320])
        #expect(transitions.map(\.on) == [false, true])
    }

    @Test func edgeCases() {
        #expect(ShellyScheduleBuilder.transitions(onHours: []).isEmpty)
        let always = ShellyScheduleBuilder.transitions(onHours: Array(0..<24))
        #expect(always.count == 1 && always[0].on && always[0].minute == 0)
    }

    @Test func tooManyWindowsAreMergedToFitDeviceLimit() {
        // 12 alternating one-hour windows need 24 jobs; the device allows 20.
        let transitions = ShellyScheduleBuilder.transitions(onHours: Array(stride(from: 0, to: 24, by: 2)))
        #expect(transitions.count <= ShellyScheduleBuilder.maxJobs)
        #expect(transitions.filter(\.on).count == transitions.filter { !$0.on }.count)
    }

    @Test func shiftsToDeviceTimeZone() {
        let schedule = PlugSchedule(onHours: [2], timeZoneIdentifier: "America/New_York", createdAt: created)
        let jobs = ShellyScheduleBuilder.jobs(for: schedule, deviceTimeZone: TimeZone(identifier: "America/Los_Angeles"))
        #expect(jobs.map(\.timespec) == ["0 0 23 * * SUN,MON,TUE,WED,THU,FRI,SAT", "0 0 0 * * SUN,MON,TUE,WED,THU,FRI,SAT"])
        let kolkata = ShellyScheduleBuilder.jobs(for: PlugSchedule(onHours: [2], timeZoneIdentifier: "UTC", createdAt: created),
                                                 deviceTimeZone: TimeZone(identifier: "Asia/Kolkata"))
        #expect(kolkata.first?.timespec == "0 30 7 * * SUN,MON,TUE,WED,THU,FRI,SAT")
    }

    @Test func replaceRequestsMatchShellyRPCJSON() throws {
        let schedule = PlugSchedule(onHours: [3], timeZoneIdentifier: "UTC", createdAt: created)
        let bodies = try ShellyScheduleBuilder.replaceRequests(for: schedule).map { String(decoding: $0, as: UTF8.self) }
        #expect(bodies == [
            #"{"id":1,"method":"Schedule.DeleteAll"}"#,
            #"{"id":2,"method":"Schedule.Create","params":{"calls":[{"method":"Switch.Set","params":{"id":0,"on":true}}],"enable":true,"timespec":"0 0 3 * * SUN,MON,TUE,WED,THU,FRI,SAT"}}"#,
            #"{"id":3,"method":"Schedule.Create","params":{"calls":[{"method":"Switch.Set","params":{"id":0,"on":false}}],"enable":true,"timespec":"0 0 4 * * SUN,MON,TUE,WED,THU,FRI,SAT"}}"#,
        ])
    }
}
