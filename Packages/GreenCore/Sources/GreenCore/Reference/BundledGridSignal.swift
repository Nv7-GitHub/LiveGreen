import Foundation

/// Offline `GridSignal` from the bundled regional 24-hour shapes (spec §8.3 fallback). Every point is estimated.
public struct BundledGridSignal: GridSignal {
    public let store: ReferenceStore
    public let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(store: ReferenceStore = .bundled, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    /// The zone's record, else the US average.
    public func record(zone: String) throws -> RegionalGridIntensity {
        guard let record = store.gridIntensity(region: zone) ?? store.gridIntensity(region: "US") else {
            throw GreenCoreError.notFound
        }
        return record
    }

    public func latest(zone: String) async throws -> GridIntensityPoint {
        let date = now()
        return GridIntensityPoint(date: date, gramsCO2ePerKWh: try record(zone: zone).intensity(atHour: calendar.component(.hour, from: date)),
                                  zone: zone, isEstimated: true)
    }

    public func history(zone: String, hours: Int) async throws -> [GridIntensityPoint] {
        let record = try record(zone: zone)
        let end = now()
        return (0..<max(hours, 0)).reversed().map { offset in
            let date = end.addingTimeInterval(-Double(offset) * 3600)
            return GridIntensityPoint(date: date, gramsCO2ePerKWh: record.intensity(atHour: calendar.component(.hour, from: date)),
                                      zone: zone, isEstimated: true)
        }
    }
}
