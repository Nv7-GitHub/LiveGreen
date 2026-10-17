import Foundation

/// Grid carbon-intensity signal (spec §8.3: Electricity Maps or the free EIA API, falling back to the bundled 24-h shape).
public protocol GridSignal: Sendable {
    /// Current (or most recently published) intensity for an Electricity Maps-style zone (e.g. "US-NE-ISNE").
    func latest(zone: String) async throws -> GridIntensityPoint
    /// Hourly history, oldest first, covering roughly the last `hours` hours.
    func history(zone: String, hours: Int) async throws -> [GridIntensityPoint]
}

/// One hourly grid intensity reading.
public struct GridIntensityPoint: Codable, Sendable, Hashable {
    public var date: Date
    public var gramsCO2ePerKWh: Double
    public var zone: String
    /// True for modeled/fallback values rather than measured data.
    public var isEstimated: Bool

    public init(date: Date, gramsCO2ePerKWh: Double, zone: String, isEstimated: Bool = false) {
        self.date = date
        self.gramsCO2ePerKWh = gramsCO2ePerKWh
        self.zone = zone
        self.isEstimated = isEstimated
    }
}
