import Foundation

/// A Shelly Gen2+ smart plug over its local HTTP RPC API (spec §8.2–8.3). Requests are retried once
/// with HTTP Digest (SHA-256) credentials when the device answers 401 and a password is configured.
public struct ShellyClient: PlugController {
    public var endpoint: PlugEndpoint
    /// Device password when authentication is enabled on the plug (user "admin").
    public var password: String?
    public var timeout: Double
    let transport: any HTTPTransport
    let makeCNonce: @Sendable () -> String
    let now: @Sendable () -> Date

    public init(endpoint: PlugEndpoint, password: String? = nil, timeout: Double = 5,
                transport: any HTTPTransport = URLSessionTransport(),
                makeCNonce: (@Sendable () -> String)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.endpoint = endpoint
        self.password = password
        self.timeout = timeout
        self.transport = transport
        self.makeCNonce = makeCNonce ?? { ShellyDigestChallenge.makeCNonce() }
        self.now = now
    }

    public func deviceInfo() async throws -> PlugDeviceInfo {
        let info: ShellyDeviceInfoResult
        do {
            info = try await call("Shelly.GetDeviceInfo", params: NoParams?.none)
        } catch GreenCoreError.http(status: 404, _) {
            throw GreenCoreError.unsupported("This Shelly does not expose the Gen2 RPC API (Gen1 devices are not supported).")
        }
        guard let generation = info.gen, generation >= 2 else {
            throw GreenCoreError.unsupported("Shelly Gen1 devices are not supported.")
        }
        return PlugDeviceInfo(id: info.id, model: info.model ?? "Shelly", generation: generation,
                              firmware: info.ver ?? "unknown", name: info.name, authEnabled: info.authEn ?? false)
    }

    public func status() async throws -> PlugStatus {
        let result: ShellySwitchStatusResult = try await call("Switch.GetStatus", params: SwitchID())
        return PlugStatus(isOn: result.output, activePowerW: result.apower ?? 0,
                          totalEnergyWh: result.aenergy?.total ?? 0, temperatureC: result.temperature?.tC, timestamp: now())
    }

    public func setSwitch(on: Bool) async throws {
        try await perform("Switch.Set", params: SwitchSetParams(id: 0, on: on))
    }

    /// Sets the plug's time zone, replaces every job with the plan, then puts the switch in the state
    /// the plan calls for right now so the plug is consistent before the next boundary.
    public func replaceSchedule(_ schedule: PlugSchedule) async throws {
        try await perform("Sys.SetConfig", params: ShellyTimeZoneConfig(timeZone: schedule.timeZoneIdentifier))
        try await perform("Schedule.DeleteAll", params: NoParams?.none)
        for job in ShellySchedulePlan.jobs(for: schedule) {
            try await perform("Schedule.Create", params: job)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
        try await setSwitch(on: ShellySchedulePlan.isOn(schedule, atHour: calendar.component(.hour, from: now())))
    }

    /// Jobs currently stored on the plug (`Schedule.List`).
    public func scheduledJobs() async throws -> [ShellyScheduleJob] {
        let result: ShellyScheduleListResult = try await call("Schedule.List", params: NoParams?.none)
        return result.jobs
    }

    func call<Params: Encodable & Sendable, Result: Decodable>(_ method: String, params: Params?) async throws -> Result {
        guard let result = try await envelope(method, params: params, as: Result.self).result else {
            throw GreenCoreError.decoding("Shelly \(method): missing result")
        }
        return result
    }

    /// For calls whose result is not needed (`Switch.Set`, `Schedule.*`); only RPC errors matter.
    func perform<Params: Encodable & Sendable>(_ method: String, params: Params?) async throws {
        _ = try await envelope(method, params: params, as: JSONValue.self)
    }

    private func envelope<Params: Encodable & Sendable, Result: Decodable>(
        _ method: String, params: Params?, as _: Result.Type) async throws -> ShellyRPCResponse<Result> {
        guard let url = endpoint.baseURL?.appending(path: "rpc") else {
            throw GreenCoreError.unsupported("Invalid plug address \(endpoint.host)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        request.httpBody = try encoder.encode(ShellyRPCRequest(id: 1, method: method, params: params))

        var (data, response) = try await transport.send(request)
        if response.statusCode == 401 {
            guard let password = password?.trimmedNonEmpty,
                  let header = response.value(forHTTPHeaderField: "WWW-Authenticate"),
                  let challenge = ShellyDigestChallenge(header: header) else {
                throw GreenCoreError.http(status: 401, body: "The plug requires its password.")
            }
            request.setValue(challenge.authorization(password: password, method: "POST", uri: "/rpc", cnonce: makeCNonce()),
                             forHTTPHeaderField: "Authorization")
            (data, response) = try await transport.send(request)
        }
        guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }

        let envelope: ShellyRPCResponse<Result>
        do {
            envelope = try JSONDecoder().decode(ShellyRPCResponse<Result>.self, from: data)
        } catch {
            throw GreenCoreError.decoding("Shelly \(method): \(error)")
        }
        if let error = envelope.error { throw GreenCoreError.http(status: error.code, body: "\(method): \(error.message)") }
        return envelope
    }
}
