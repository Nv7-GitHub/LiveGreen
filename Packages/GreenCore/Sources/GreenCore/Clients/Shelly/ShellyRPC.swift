import Foundation

struct ShellyRPCResponse<Result: Decodable>: Decodable {
    struct RPCError: Decodable {
        var code: Int
        var message: String
    }
    var id: Int?
    var result: Result?
    var error: RPCError?
}

/// Parameter-less calls encode `params` as absent.
struct NoParams: Encodable, Sendable {}

struct SwitchID: Encodable, Sendable {
    var id: Int = 0
}

/// `Shelly.GetDeviceInfo` result.
struct ShellyDeviceInfoResult: Decodable {
    var id: String
    var model: String?
    var gen: Int?
    var ver: String?
    var name: String?
    var authEn: Bool?

    enum CodingKeys: String, CodingKey {
        case id, model, gen, ver, name
        case authEn = "auth_en"
    }
}

/// `Switch.GetStatus` result.
struct ShellySwitchStatusResult: Decodable {
    struct Energy: Decodable {
        var total: Double?
    }
    struct Temperature: Decodable {
        var tC: Double?
    }
    var output: Bool
    var apower: Double?
    var aenergy: Energy?
    var temperature: Temperature?
}

/// `Schedule.List` result.
struct ShellyScheduleListResult: Decodable {
    var jobs: [ShellyScheduleJob]
}

/// `Sys.SetConfig` params setting the device time zone, so schedule hours match the plan's local hours.
struct ShellyTimeZoneConfig: Encodable, Sendable {
    struct Config: Encodable, Sendable {
        struct Location: Encodable, Sendable {
            var tz: String
        }
        var location: Location
    }
    var config: Config

    init(timeZone: String) {
        config = Config(location: .init(tz: timeZone))
    }
}
