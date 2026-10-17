import Foundation

/// Where to read grid intensity for: an Electricity Maps zone or a coordinate the API maps to a zone.
public enum GridLocation: Sendable, Hashable {
    case zone(String)
    case coordinate(latitude: Double, longitude: Double)

    var queryItems: [URLQueryItem] {
        switch self {
        case .zone(let zone):
            [URLQueryItem(name: "zone", value: zone)]
        case .coordinate(let latitude, let longitude):
            [URLQueryItem(name: "lat", value: String(latitude)), URLQueryItem(name: "lon", value: String(longitude))]
        }
    }
}

/// Electricity Maps v3 grid carbon intensity (spec §8.3): `/v3/carbon-intensity/latest` and `/history`
/// (last 24 h), plus `/past-range` for longer windows, authenticated with the `auth-token` header.
public struct ElectricityMapsClient: GridSignal {
    /// `ELECTRICITYMAPS_API_KEY`. Calls throw `GreenCoreError.missingAPIKey` while it is nil or empty.
    public var apiKey: String?
    public var baseURL: URL
    public var timeout: Double
    public var retry: RetryPolicy
    let transport: any HTTPTransport
    /// Injected for tests; used to compute `/past-range` windows.
    let now: @Sendable () -> Date

    public init(apiKey: String?, baseURL: URL = URL(string: "https://api.electricitymap.org")!, timeout: Double = 10,
                retry: RetryPolicy = .default, transport: any HTTPTransport = URLSessionTransport(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        self.retry = retry
        self.transport = transport
        self.now = now
    }

    public func latest(zone: String) async throws -> GridIntensityPoint {
        try await latest(at: .zone(zone))
    }

    public func history(zone: String, hours: Int) async throws -> [GridIntensityPoint] {
        try await history(at: .zone(zone), hours: hours)
    }

    public func latest(at location: GridLocation) async throws -> GridIntensityPoint {
        let reading: Reading = try await get("v3/carbon-intensity/latest", location.queryItems)
        guard let point = reading.point(fallbackZone: location.zoneName) else {
            throw GreenCoreError.decoding("Electricity Maps latest reading has no carbonIntensity")
        }
        return point
    }

    /// Hourly readings, oldest first. Up to 24 h uses `/history`; longer windows use `/past-range`.
    public func history(at location: GridLocation, hours: Int) async throws -> [GridIntensityPoint] {
        let hours = max(hours, 1)
        let list: ReadingList
        if hours <= 24 {
            list = try await get("v3/carbon-intensity/history", location.queryItems)
        } else {
            let end = now()
            let start = end.addingTimeInterval(-Double(hours) * 3600)
            list = try await get("v3/carbon-intensity/past-range", location.queryItems + [
                URLQueryItem(name: "start", value: Self.timestamp(start)),
                URLQueryItem(name: "end", value: Self.timestamp(end)),
            ])
        }
        let zone = list.zone ?? location.zoneName
        let points = list.readings.compactMap { $0.point(fallbackZone: zone) }.sorted { $0.date < $1.date }
        return Array(points.suffix(hours))
    }

    func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        guard let apiKey = apiKey?.trimmedNonEmpty else { throw GreenCoreError.missingAPIKey("ELECTRICITYMAPS_API_KEY") }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = timeout
        request.setValue(apiKey, forHTTPHeaderField: "auth-token")
        let (data, response) = try await retry.send(request, via: transport)
        guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GreenCoreError.decoding("Electricity Maps \(path): \(error)")
        }
    }

    static func timestamp(_ date: Date) -> String {
        Date.ISO8601FormatStyle().format(date)
    }

    static func parseDate(_ raw: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
            ?? (try? Date.ISO8601FormatStyle().parse(raw))
    }

    /// One reading as returned by `latest` and inside `history` / `data` arrays.
    struct Reading: Decodable {
        var zone: String?
        var carbonIntensity: Double?
        var datetime: String
        var isEstimated: Bool?

        func point(fallbackZone: String) -> GridIntensityPoint? {
            guard let carbonIntensity, let date = ElectricityMapsClient.parseDate(datetime) else { return nil }
            return GridIntensityPoint(date: date, gramsCO2ePerKWh: carbonIntensity, zone: zone ?? fallbackZone,
                                      isEstimated: isEstimated ?? false)
        }
    }

    /// `/history` returns `{zone, history: […]}`; `/past-range` returns `{zone, data: […]}`.
    struct ReadingList: Decodable {
        var zone: String?
        var readings: [Reading]

        enum CodingKeys: String, CodingKey { case zone, history, data }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            zone = try container.decodeIfPresent(String.self, forKey: .zone)
            readings = try container.decodeIfPresent([Reading].self, forKey: .history)
                ?? container.decodeIfPresent([Reading].self, forKey: .data) ?? []
        }
    }
}

extension GridLocation {
    var zoneName: String {
        switch self {
        case .zone(let zone): zone
        case .coordinate(let latitude, let longitude): String(format: "%.3f,%.3f", latitude, longitude)
        }
    }
}
