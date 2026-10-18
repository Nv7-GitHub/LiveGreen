import Foundation
import Testing
@testable import GreenCore

@Suite("ShellyClient")
struct ShellyClientTests {
    static let endpoint = PlugEndpoint(host: "192.168.1.42")
    static let ok = MockTransport.Reply.json("{\"id\":1,\"result\":{\"was_on\":false}}")
    /// 2026-10-16 14:30 in New York.
    static let afternoon = Date(timeIntervalSince1970: 1_792_175_400)

    func client(_ transport: MockTransport, password: String? = nil) -> ShellyClient {
        ShellyClient(endpoint: Self.endpoint, password: password, transport: transport,
                     makeCNonce: { "0a4f113b" }, now: { Self.afternoon })
    }

    @Test func deviceInfo() async throws {
        let transport = MockTransport([.fixture("shelly/device_info.json")])
        let info = try await client(transport).deviceInfo()
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://192.168.1.42:80/rpc")
        #expect(request.httpMethod == "POST")
        #expect(request.jsonBody == ["id": 1, "method": "Shelly.GetDeviceInfo"])
        #expect(info == PlugDeviceInfo(id: "shellyplugus-d4d4dae0a1b2", model: "SNPL-00116US", generation: 2,
                                       firmware: "1.4.4", name: "E-bike charger", authEnabled: true))
    }

    @Test func gen1IsUnsupported() async throws {
        let transport = MockTransport([.json("Not Found", status: 404)])
        await #expect(throws: GreenCoreError.self) { _ = try await client(transport).deviceInfo() }
        do {
            _ = try await client(MockTransport([.json("Not Found", status: 404)])).deviceInfo()
        } catch GreenCoreError.unsupported {
            // expected
        } catch {
            Issue.record("expected unsupported, got \(error)")
        }
    }

    @Test func statusAndSwitch() async throws {
        let transport = MockTransport([.fixture("shelly/switch_status.json"), Self.ok])
        let shelly = client(transport)
        let status = try await shelly.status()
        #expect(status == PlugStatus(isOn: true, activePowerW: 168.4, totalEnergyWh: 5321.775, temperatureC: 41.3,
                                     timestamp: Self.afternoon))
        try await shelly.setSwitch(on: false)
        #expect(transport.requests[0].jsonBody == ["id": 1, "method": "Switch.GetStatus", "params": ["id": 0]])
        #expect(transport.requests[1].jsonBody == ["id": 1, "method": "Switch.Set", "params": ["id": 0, "on": false]])
    }

    @Test func digestAuthOn401() async throws {
        let challenge = "Digest qop=\"auth\", realm=\"shellyplugus-d4d4dae0a1b2\", nonce=\"60dc59c6\", algorithm=SHA-256"
        let transport = MockTransport([
            .json("", status: 401).with(headers: ["WWW-Authenticate": challenge]),
            .fixture("shelly/switch_status.json"),
        ])
        _ = try await client(transport, password: "hunter2").status()

        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        let header = try #require(transport.requests[1].value(forHTTPHeaderField: "Authorization"))
        let ha1 = ShellyDigestChallenge.sha256Hex("admin:shellyplugus-d4d4dae0a1b2:hunter2")
        let ha2 = ShellyDigestChallenge.sha256Hex("POST:/rpc")
        let expected = ShellyDigestChallenge.sha256Hex("\(ha1):60dc59c6:00000001:0a4f113b:auth:\(ha2)")
        #expect(header.hasPrefix("Digest username=\"admin\", realm=\"shellyplugus-d4d4dae0a1b2\", nonce=\"60dc59c6\", uri=\"/rpc\""))
        #expect(header.contains("response=\"\(expected)\""))
        #expect(header.contains("qop=auth, nc=00000001, cnonce=\"0a4f113b\""))
        #expect(header.contains("algorithm=SHA-256"))
    }

    @Test func unauthorizedWithoutPassword() async throws {
        let transport = MockTransport([.json("", status: 401).with(headers: ["WWW-Authenticate": "Digest realm=\"x\", nonce=\"y\""])])
        await #expect(throws: GreenCoreError.http(status: 401, body: "The plug requires its password.")) {
            _ = try await client(transport).status()
        }
    }

    @Test func rpcErrorThrows() async throws {
        let transport = MockTransport([.fixture("shelly/rpc_error.json")])
        await #expect(throws: GreenCoreError.http(status: -103, body: "Switch.GetStatus: Invalid argument 'id': no such component")) {
            _ = try await client(transport).status()
        }
    }

    @Test func replaceScheduleWritesJobsAndCurrentState() async throws {
        let transport = MockTransport(Array(repeating: Self.ok, count: 5))
        let schedule = PlugSchedule(onHours: [1, 2, 3, 13, 14], timeZoneIdentifier: "America/New_York")
        try await client(transport).replaceSchedule(schedule)

        let bodies = transport.requests.compactMap(\.jsonBody)
        #expect(bodies.map { $0["method"]?.string } == ["Sys.SetConfig", "Schedule.DeleteAll", "Schedule.Create",
                                                        "Schedule.Create", "Switch.Set"])
        #expect(bodies[0]["params"] == ["config": ["location": ["tz": "America/New_York"]]])
        #expect(bodies[2]["params"] == ["enable": true, "timespec": "0 0 1,13 * * *",
                                        "calls": [["method": "Switch.Set", "params": ["id": 0, "on": true]]]])
        #expect(bodies[3]["params"]?["timespec"]?.string == "0 0 4,15 * * *")
        #expect(bodies[4]["params"] == ["id": 0, "on": true], "14:30 local is inside the 13–15 window")
    }

    @Test func listsJobs() async throws {
        let transport = MockTransport([.fixture("shelly/schedule_list.json")])
        let jobs = try await client(transport).scheduledJobs()
        #expect(jobs.map(\.timespec) == ["0 0 1,13 * * *", "0 0 4,15 * * *"])
        #expect(jobs.map(\.switchOn) == [true, false])
    }

    @Test func challengeParsing() throws {
        let challenge = try #require(ShellyDigestChallenge(header: "Digest qop=\"auth,auth-int\", realm=\"a,b\", nonce=\"n1\""))
        #expect(challenge.realm == "a,b")
        #expect(challenge.qop == "auth")
        #expect(challenge.algorithm == "SHA-256")
        #expect(ShellyDigestChallenge(header: "Basic realm=\"x\"") == nil)
    }
}

@Suite("Shelly schedule plan")
struct ShellySchedulePlanTests {
    @Test func windowsBecomeOnAndOffJobs() {
        let jobs = ShellySchedulePlan.jobs(for: PlugSchedule(onHours: [2, 3, 10]))
        #expect(jobs == [ShellyScheduleJob(timespec: "0 0 2,10 * * *", switchOn: true),
                         ShellyScheduleJob(timespec: "0 0 4,11 * * *", switchOn: false)])
    }

    @Test func wrapsPastMidnight() {
        let jobs = ShellySchedulePlan.jobs(for: PlugSchedule(onHours: [22, 23, 0, 1]))
        #expect(jobs.map(\.timespec) == ["0 0 22 * * *", "0 0 2 * * *"])
    }

    @Test func endAtMidnightTurnsOffAtZero() {
        let jobs = ShellySchedulePlan.jobs(for: PlugSchedule(onHours: [21, 22, 23]))
        #expect(jobs.map(\.timespec) == ["0 0 21 * * *", "0 0 0 * * *"])
    }

    @Test func fullDayAndEmpty() {
        #expect(ShellySchedulePlan.jobs(for: PlugSchedule(onHours: Array(0..<24))) ==
                [ShellyScheduleJob(timespec: "0 0 0 * * *", switchOn: true)])
        #expect(ShellySchedulePlan.jobs(for: PlugSchedule(onHours: [])).isEmpty)
    }
}

extension MockTransport.Reply {
    func with(headers: [String: String]) -> Self {
        var copy = self
        copy.headers = headers
        return copy
    }
}
