import Foundation

/// Controls one smart plug (spec §8: Shelly Gen2+ local RPC).
public protocol PlugController: Sendable {
    /// `Shelly.GetDeviceInfo`. Throws `GreenCoreError.unsupported` for Gen1 devices.
    func deviceInfo() async throws -> PlugDeviceInfo
    /// `Switch.GetStatus` for switch 0.
    func status() async throws -> PlugStatus
    /// `Switch.Set` (manual override).
    func setSwitch(on: Bool) async throws
    /// Replaces all schedules on the plug (`Schedule.DeleteAll` + `Schedule.Create` per window),
    /// so the plug enforces the plan when the app is closed.
    func replaceSchedule(_ schedule: PlugSchedule) async throws
}

/// Network location of a discovered/entered plug.
public struct PlugEndpoint: Codable, Sendable, Hashable {
    public var host: String
    public var port: Int
    /// Bonjour service name, if discovered.
    public var serviceName: String?

    public init(host: String, port: Int = 80, serviceName: String? = nil) {
        self.host = host
        self.port = port
        self.serviceName = serviceName
    }

    public var baseURL: URL? { URL(string: "http://\(host):\(port)") }
}

/// `Shelly.GetDeviceInfo` subset.
public struct PlugDeviceInfo: Codable, Sendable, Hashable {
    public var id: String
    public var model: String
    public var generation: Int
    public var firmware: String
    public var name: String?
    public var authEnabled: Bool

    public init(id: String, model: String, generation: Int, firmware: String, name: String? = nil, authEnabled: Bool = false) {
        self.id = id
        self.model = model
        self.generation = generation
        self.firmware = firmware
        self.name = name
        self.authEnabled = authEnabled
    }
}

/// `Switch.GetStatus` subset.
public struct PlugStatus: Codable, Sendable, Hashable {
    public var isOn: Bool
    /// `apower`, W.
    public var activePowerW: Double
    /// `aenergy.total`, Wh.
    public var totalEnergyWh: Double
    public var temperatureC: Double?
    public var timestamp: Date

    public init(isOn: Bool, activePowerW: Double, totalEnergyWh: Double, temperatureC: Double? = nil, timestamp: Date = Date()) {
        self.isOn = isOn
        self.activePowerW = activePowerW
        self.totalEnergyWh = totalEnergyWh
        self.temperatureC = temperatureC
        self.timestamp = timestamp
    }
}

/// A daily green-hours plan: the plug is on during `onHours` (local hours 0–23), off otherwise.
public struct PlugSchedule: Codable, Sendable, Hashable {
    public var onHours: [Int]
    public var timeZoneIdentifier: String
    public var createdAt: Date
    /// Mean grid intensity over the chosen hours, gCO2e/kWh.
    public var expectedIntensity: Double?

    public init(onHours: [Int], timeZoneIdentifier: String = TimeZone.current.identifier,
                createdAt: Date = Date(), expectedIntensity: Double? = nil) {
        self.onHours = Array(Set(onHours.filter { (0..<24).contains($0) })).sorted()
        self.timeZoneIdentifier = timeZoneIdentifier
        self.createdAt = createdAt
        self.expectedIntensity = expectedIntensity
    }

    /// Contiguous on-windows as half-open hour ranges, e.g. [1..<4, 13..<15].
    public var windows: [Range<Int>] {
        var result: [Range<Int>] = []
        for hour in onHours {
            if let last = result.last, last.upperBound == hour {
                result[result.count - 1] = last.lowerBound..<(hour + 1)
            } else {
                result.append(hour..<(hour + 1))
            }
        }
        return result
    }
}
