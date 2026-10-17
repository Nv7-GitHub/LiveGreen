import Foundation
import GreenCore

/// Deterministic diurnal grid curve: dirtier evenings, a solar dip around midday, cleanest overnight.
public struct FakeGridSignal: GridSignal {
    public var averageGPerKWh: Double

    public init(averageGPerKWh: Double = 280) {
        self.averageGPerKWh = averageGPerKWh
    }

    /// Modeled intensity at a local hour of day.
    public func intensity(atHour hour: Int) -> Double {
        let h = Double(((hour % 24) + 24) % 24)
        let evening = 0.25 * exp(-pow(h - 19, 2) / 8)
        let solar = -0.20 * exp(-pow(h - 13, 2) / 6)
        let night = -0.12 * exp(-pow(h - 3, 2) / 6)
        return averageGPerKWh * (1 + evening + solar + night)
    }

    public func latest(zone: String) async throws -> GridIntensityPoint {
        let hour = Calendar.current.component(.hour, from: Date())
        return GridIntensityPoint(date: Date(), gramsCO2ePerKWh: intensity(atHour: hour), zone: zone, isEstimated: true)
    }

    public func history(zone: String, hours: Int) async throws -> [GridIntensityPoint] {
        let now = Date()
        return (0..<max(hours, 0)).reversed().map { offset in
            let date = now.addingTimeInterval(-Double(offset) * 3600)
            let hour = Calendar.current.component(.hour, from: date)
            return GridIntensityPoint(date: date, gramsCO2ePerKWh: intensity(atHour: hour), zone: zone, isEstimated: true)
        }
    }
}
