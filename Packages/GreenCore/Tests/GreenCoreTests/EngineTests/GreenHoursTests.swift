import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Green-hours forecast and planner")
struct GreenHoursTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// 2026-10-16 18:30 local.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 18, minute: 30))! }

    /// Clean overnight (hours 1–4 = 100), cleanest at 3 (80), solar dip at 13 (150), 300 elsewhere.
    var forecast: GridForecast {
        var hourly = [Double](repeating: 300, count: 24)
        for hour in 1...4 { hourly[hour] = 100 }
        hourly[3] = 80
        hourly[13] = 150
        return GridForecast(hourly: hourly, isFallback: false)
    }

    @Test func forecastIsMedianOfSameHourOverLastWeek() throws {
        var history: [GridIntensityPoint] = []
        for day in 1...7 {
            for hour in 0..<24 {
                let date = calendar.date(byAdding: .hour, value: -(day * 24) + hour + 1, to: now)!
                let h = calendar.component(.hour, from: date)
                // Hour 5 alternates 100/200/... so its median is checkable; one stale outlier is outside the window.
                let value = h == 5 ? Double(day) * 100 : Double(h) + 200
                history.append(GridIntensityPoint(date: date, gramsCO2ePerKWh: value, zone: "TEST"))
            }
        }
        history.append(GridIntensityPoint(date: now.addingTimeInterval(-9 * 86_400), gramsCO2ePerKWh: 99_999, zone: "TEST"))
        let result = try #require(GridForecast.make(history: history, fallback: nil, now: now, calendar: calendar))
        #expect(!result.isFallback)
        #expect(result.intensity(atHour: 5) == 400) // median of 100…700
        #expect(result.intensity(atHour: 10) == 210)
    }

    @Test func missingHoursUseScaledBundledShape() throws {
        let record = RegionalGridIntensity(region: "T", annualAverageGPerKWh: 100, hourlyShape: [Double](repeating: 1, count: 24),
                                           citation: Source(title: "Test shape", tier: .factorModel))
        let point = GridIntensityPoint(date: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!, gramsCO2ePerKWh: 300, zone: "T")
        let result = try #require(GridForecast.make(history: [point], fallback: record, now: now, calendar: calendar))
        #expect(result.intensity(atHour: 12) == 300)
        #expect(result.intensity(atHour: 2) == 300) // shape rescaled to the observed level
        let fallbackOnly = try #require(GridForecast.make(history: [], fallback: record, now: now, calendar: calendar))
        #expect(fallbackOnly.isFallback && fallbackOnly.dayAverage == 100)
        #expect(GridForecast.make(history: [], fallback: nil, now: now, calendar: calendar) == nil)
    }

    @Test func choosesCleanestHoursBeforeDeadline() {
        // From 19:00 until 07:00: 12 candidate hours.
        let plan = GreenHoursPlanner.plan(forecast: forecast, requiredHours: 2.4, now: now, deadlineHour: 7, calendar: calendar)
        #expect(plan.plannedHours == 3)
        #expect(plan.fitsDeadline)
        #expect(plan.contiguous.hours == [1, 2, 3]) // ties with [2, 3, 4]; earliest wins
        #expect(plan.contiguous.isContiguous)
        #expect(abs(plan.contiguous.averageIntensity - 280.0 / 3) < 1e-9)
        #expect(plan.flexible.hours == [1, 3, 4] || plan.flexible.hours == [1, 2, 3])
        #expect(plan.flexible.averageIntensity <= plan.contiguous.averageIntensity)
    }

    @Test func noDeadlineSearchesNext24HoursAndSplitsWhenCheaper() {
        var hourly = [Double](repeating: 300, count: 24)
        hourly[2] = 50
        hourly[14] = 60
        let plan = GreenHoursPlanner.plan(forecast: GridForecast(hourly: hourly, isFallback: false), requiredHours: 2,
                                          now: now, calendar: calendar)
        #expect(plan.flexible.hours == [2, 14])
        #expect(!plan.flexible.isContiguous)
        #expect(plan.contiguous.hours.count == 2)
        #expect(plan.flexible.schedule(timeZone: calendar.timeZone).onHours == [2, 14])
    }

    @Test func deadlineTooTightUsesEveryAvailableHour() {
        let plan = GreenHoursPlanner.plan(forecast: forecast, requiredHours: 5, now: now, deadlineHour: 22, calendar: calendar)
        #expect(!plan.fitsDeadline)
        #expect(plan.contiguous.hours == [19, 20, 21])
        #expect(GreenHoursPlanner.plan(forecast: forecast, requiredHours: 0, now: now, calendar: calendar).flexible.hours.isEmpty)
    }

    @Test func savingsFormula() {
        // 90 kWh/yr × (280 − 180) g/kWh ÷ 1000 = 9 kg.
        #expect(abs(GreenHoursPlanner.yearlySavingsKg(kWhPerYear: 90, averageIntensity: 280, windowIntensity: 180) - 9) < 1e-12)
        #expect(GreenHoursPlanner.yearlySavingsKg(kWhPerYear: 90, averageIntensity: 100, windowIntensity: 180) == 0)
        let measured = GreenHoursPlanner.accumulatedSavingsKg(samples: [(1, 100), (2, 400)], dayAverage: 300)
        #expect(abs(measured - (0.2 - 0.2)) < 1e-12)
    }

    @Test func estimatedSavingsForEBikeCharger() {
        let candidate = PlugCandidate(loadType: .eBike, chargerWatts: 170, dailyKWh: 0.255)
        let fake = FakeGridSignal()
        let forecast = GridForecast(hourly: (0..<24).map(fake.intensity(atHour:)), isFallback: true)
        let savings = GreenHoursPlanner.estimatedSavings(for: candidate, forecast: forecast, now: now, calendar: calendar)
        let plan = GreenHoursPlanner.plan(forecast: forecast, requiredHours: candidate.requiredHoursPerDay, now: now, calendar: calendar)
        #expect(plan.plannedHours == 2)
        let expected = 0.255 * 365 * (forecast.dayAverage - plan.flexible.averageIntensity) / 1000
        #expect(abs(savings.value - expected) < 1e-9)
        #expect(savings.value > 0 && savings.tier == .factorModel && savings.unit == .kgCO2e)
    }

    @Test func bundledGridSignalFollowsShape() async throws {
        let fixed = now
        let signal = BundledGridSignal(calendar: calendar, now: { fixed })
        let history = try await signal.history(zone: "US-NE-ISNE", hours: 48)
        #expect(history.count == 48)
        #expect(history.allSatisfy { $0.isEstimated })
        let record = try signal.record(zone: "US-NE-ISNE")
        let latest = try await signal.latest(zone: "US-NE-ISNE")
        #expect(latest.gramsCO2ePerKWh == record.intensity(atHour: 18))
        let forecast = try #require(GridForecast.make(history: history, fallback: record, now: fixed, calendar: calendar))
        #expect(abs(forecast.dayAverage - record.annualAverageGPerKWh) < 0.5)
    }
}
