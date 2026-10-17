import Foundation
import GreenCore

/// Shelly Gen2+ plug over the local JSON-RPC API (`POST /rpc`), with optional digest auth.
/// App-side PlugController; the integrator may swap in GreenCore's ShellyClient via `PlugConnector`.
nonisolated struct ShellyLocalController: PlugController {
    let endpoint: PlugEndpoint
    let password: String?
    var session: URLSession = .shared
    var timeout: TimeInterval = 6

    func deviceInfo() async throws -> PlugDeviceInfo {
        let result: [String: Any]
        do {
            result = try await call("Shelly.GetDeviceInfo")
        } catch GreenCoreError.http(status: 404, _) {
            throw try await gen1Error()
        }
        let generation = result["gen"] as? Int ?? 1
        guard generation >= 2 else { throw GreenCoreError.unsupported("Shelly Gen1 devices are not supported") }
        guard let id = result["id"] as? String else { throw GreenCoreError.decoding("Shelly.GetDeviceInfo has no id") }
        return PlugDeviceInfo(id: id,
                              model: result["model"] as? String ?? "Shelly",
                              generation: generation,
                              firmware: result["ver"] as? String ?? result["fw_id"] as? String ?? "unknown",
                              name: result["name"] as? String,
                              authEnabled: result["auth_en"] as? Bool ?? false)
    }

    func status() async throws -> PlugStatus {
        let result = try await call("Switch.GetStatus", params: ["id": 0])
        guard let isOn = result["output"] as? Bool else { throw GreenCoreError.decoding("Switch.GetStatus has no output") }
        let energy = result["aenergy"] as? [String: Any]
        let temperature = result["temperature"] as? [String: Any]
        return PlugStatus(isOn: isOn,
                          activePowerW: Self.double(result["apower"]) ?? 0,
                          totalEnergyWh: Self.double(energy?["total"]) ?? 0,
                          temperatureC: Self.double(temperature?["tC"]),
                          timestamp: Date())
    }

    func setSwitch(on: Bool) async throws {
        _ = try await call("Switch.Set", params: ["id": 0, "on": on])
    }

    func replaceSchedule(_ schedule: PlugSchedule) async throws {
        _ = try await call("Schedule.DeleteAll")
        for job in ShellyScheduleJob.jobs(for: schedule) {
            _ = try await call("Schedule.Create", params: job.createParams)
        }
    }

    // MARK: - JSON-RPC

    private func call(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let url = endpoint.baseURL?.appending(path: "rpc") else { throw GreenCoreError.unsupported("Invalid plug address") }
        let body = try JSONSerialization.data(withJSONObject: ["id": 1, "method": method, "params": params])
        var (data, response) = try await send(url: url, body: body, authorization: nil)
        if response.statusCode == 401, let password, !password.isEmpty,
           let header = response.value(forHTTPHeaderField: "WWW-Authenticate"),
           let digest = ShellyDigestAuth(challenge: header) {
            let authorization = digest.authorization(method: "POST", uri: "/rpc", password: password)
            (data, response) = try await send(url: url, body: body, authorization: authorization)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GreenCoreError.http(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GreenCoreError.decoding("\(method) returned non-object JSON")
        }
        if let error = object["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 500
            throw GreenCoreError.http(status: code == 401 ? 401 : 500, body: error["message"] as? String ?? "\(method) failed")
        }
        return object["result"] as? [String: Any] ?? [:]
    }

    private func send(url: URL, body: Data, authorization: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GreenCoreError.decoding("Not an HTTP response") }
            return (data, http)
        } catch let error as URLError where error.code == .timedOut {
            throw GreenCoreError.timeout
        }
    }

    /// Gen1 devices have no `/rpc`; `GET /shelly` identifies them.
    private func gen1Error() async throws -> GreenCoreError {
        guard let url = endpoint.baseURL?.appending(path: "shelly") else { return .notFound }
        let (data, _) = try await session.data(for: URLRequest(url: url, timeoutInterval: timeout))
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let object, object["gen"] == nil, object["type"] != nil {
            return .unsupported("This is a Shelly Gen1 device (\(object["type"] ?? "unknown")). LiveGreen needs a Gen2 or newer plug.")
        }
        return .notFound
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
