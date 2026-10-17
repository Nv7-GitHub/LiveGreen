import Foundation

/// Free US grid carbon intensity from the EIA Open Data API (EIA-930 hourly generation by fuel type).
/// `/v2/electricity/rto/fuel-type-data` gives MWh per fuel per balancing authority each hour; intensity is the
/// generation-weighted mean of lifecycle emission factors (`EIAFuelFactors`). Data lags real time by a few
/// hours, and history goes back years, so the 7-day forecast window works on a free key. The API can take a
/// minute or more to answer, so responses are shared across callers and reused for `reuseInterval`.
public struct EIAGridClient: GridSignal {
    /// `EIA_API_KEY`. Calls throw `GreenCoreError.missingAPIKey` while it is nil or empty.
    public var apiKey: String?
    public var baseURL: URL
    public var timeout: Double
    public var retry: RetryPolicy
    /// How long a fetched window stays fresh. EIA publishes hourly, hours behind real time.
    public var reuseInterval: TimeInterval
    let transport: any HTTPTransport
    let now: @Sendable () -> Date
    let memo: EIAResponseMemo

    public init(apiKey: String?, baseURL: URL = URL(string: "https://api.eia.gov")!, timeout: Double = 120,
                retry: RetryPolicy = RetryPolicy(maxAttempts: 2), reuseInterval: TimeInterval = 15 * 60,
                transport: any HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() },
                memo: EIAResponseMemo = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        self.retry = retry
        self.reuseInterval = reuseInterval
        self.transport = transport
        self.now = now
        self.memo = memo
    }

    /// The most recent complete hour EIA has published (usually a few hours old). Asks for the same 7-day
    /// window as the forecast so both share one request whichever starts first.
    public func latest(zone: String) async throws -> GridIntensityPoint {
        let points = try await history(zone: zone, hours: 7 * 24)
        guard let last = points.last else { throw GreenCoreError.notFound }
        return last
    }

    /// Hourly intensity, oldest first, for the `hours` before now.
    public func history(zone: String, hours: Int) async throws -> [GridIntensityPoint] {
        guard let respondent = Self.respondent(forZone: zone) else { throw GreenCoreError.notFound }
        let now = now()
        let start = now.addingTimeInterval(-Double(max(hours, 1)) * 3600)
        let rows = try await memo.rows(respondent: respondent, start: start, now: now, reuseInterval: reuseInterval) {
            try await fuelMix(respondent: respondent, start: start)
        }
        return Self.intensities(rows.filter { (Self.parsePeriod($0.period) ?? .distantPast) >= start }, zone: zone)
    }

    func fuelMix(respondent: String, start: Date) async throws -> [Row] {
        guard let apiKey = apiKey?.trimmedNonEmpty else { throw GreenCoreError.missingAPIKey("EIA_API_KEY") }
        var components = URLComponents(url: baseURL.appending(path: "v2/electricity/rto/fuel-type-data/data/"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "frequency", value: "hourly"),
            URLQueryItem(name: "data[0]", value: "value"),
            URLQueryItem(name: "facets[respondent][]", value: respondent),
            URLQueryItem(name: "start", value: Self.period(start)),
            URLQueryItem(name: "sort[0][column]", value: "period"),
            URLQueryItem(name: "sort[0][direction]", value: "asc"),
            URLQueryItem(name: "length", value: "5000"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = timeout
        let (data, response) = try await retry.send(request, via: transport)
        guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }
        do {
            return try JSONDecoder().decode(Payload.self, from: data).response.data
        } catch {
            throw GreenCoreError.decoding("EIA fuel-type-data: \(error)")
        }
    }

    /// Groups rows by hour and converts each hour's fuel mix to gCO2e/kWh. Storage is left out (it shifts
    /// grid energy rather than generating it). Hours missing their main fuels are skipped: too few fuels
    /// reported, or total generation under half the window's median (EIA reporting gaps that zero out
    /// gas or nuclear for an hour would otherwise read as wildly clean or dirty).
    static func intensities(_ rows: [Row], zone: String) -> [GridIntensityPoint] {
        let hours = Dictionary(grouping: rows, by: \.period).compactMap { period, rows -> (Date, mwh: Double, grams: Double)? in
            guard let date = parsePeriod(period), rows.count >= EIAFuelFactors.minimumFuelsPerHour else { return nil }
            var mwh = 0.0, grams = 0.0
            for row in rows {
                guard let value = row.megawattHours, value > 0, let factor = EIAFuelFactors.grams(for: row.fueltype) else { continue }
                mwh += value
                grams += value * factor
            }
            return mwh > 0 ? (date, mwh, grams) : nil
        }
        let totals = hours.map(\.mwh).sorted()
        let floor = totals.isEmpty ? 0 : totals[totals.count / 2] * EIAFuelFactors.minimumShareOfMedianGeneration
        return hours.filter { $0.mwh >= floor }
            .map { GridIntensityPoint(date: $0.0, gramsCO2ePerKWh: $0.grams / $0.mwh, zone: zone) }
            .sorted { $0.date < $1.date }
    }

    /// EIA balancing-authority code for a grid zone. Electricity Maps-style US zones ("US-NE-ISNE") end in
    /// the EIA code; "US" means the lower 48. Non-US zones, Hawaii and Alaska are not in EIA-930.
    public static func respondent(forZone zone: String) -> String? {
        let parts = zone.uppercased().split(separator: "-").map(String.init)
        guard parts.first == "US" else { return nil }
        if parts.count == 1 { return "US48" }
        guard parts.count >= 3 else { return nil }
        return parts.last
    }

    /// EIA periods are UTC hours formatted "YYYY-MM-DDTHH".
    static func period(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day, .hour], from: date)
        return String(format: "%04d-%02d-%02dT%02d", c.year!, c.month!, c.day!, c.hour!)
    }

    static func parsePeriod(_ raw: String) -> Date? {
        let parts = raw.split(whereSeparator: { $0 == "-" || $0 == "T" }).compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3]))
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    struct Payload: Decodable {
        struct Response: Decodable { var data: [Row] }
        var response: Response
    }

    /// One fuel's generation in one hour. EIA sends `value` as a string (sometimes null).
    struct Row: Decodable, Sendable {
        var period: String
        var fueltype: String
        var value: String?

        var megawattHours: Double? { value.flatMap(Double.init) }
    }
}

/// Shares EIA responses per balancing authority: concurrent callers wait on one request, and a window
/// fetched within `reuseInterval` that covers the requested start is served without a new request.
public actor EIAResponseMemo {
    public static let shared = EIAResponseMemo()

    private struct Entry {
        var start: Date
        var fetchedAt: Date
        var task: Task<[EIAGridClient.Row], any Error>
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    func rows(respondent: String, start: Date, now: Date, reuseInterval: TimeInterval,
              fetch: @escaping @Sendable () async throws -> [EIAGridClient.Row]) async throws -> [EIAGridClient.Row] {
        if let entry = entries[respondent], entry.start <= start, now.timeIntervalSince(entry.fetchedAt) < reuseInterval {
            return try await entry.task.value
        }
        let task = Task { try await fetch() }
        entries[respondent] = Entry(start: start, fetchedAt: now, task: task)
        do {
            return try await task.value
        } catch {
            // Failures are not reused; the next caller tries again.
            if entries[respondent]?.fetchedAt == now { entries[respondent] = nil }
            throw error
        }
    }
}

/// Lifecycle emission factors (gCO2e/kWh) per EIA-930 fuel code: IPCC AR5 WG3 Annex III medians, the same
/// basis Electricity Maps uses. Storage codes are nil so they are excluded from the mix.
public enum EIAFuelFactors {
    /// Hours with fewer reported fuels than this are still being filled in by EIA.
    static let minimumFuelsPerHour = 3
    /// Hours generating less than this share of the window's median are treated as reporting gaps.
    static let minimumShareOfMedianGeneration = 0.5

    public static func grams(for fuel: String) -> Double? {
        switch fuel.uppercased() {
        case "COL": 820
        case "NG": 490
        case "OIL": 650
        case "NUC": 12
        case "WAT": 24
        case "WND": 11
        case "SUN", "SNB": 45
        case "GEO": 38
        case "BIO", "WOO": 230
        case "OTH", "UNK": 700
        default: nil // BAT, PS (storage) and unknown codes
        }
    }
}
