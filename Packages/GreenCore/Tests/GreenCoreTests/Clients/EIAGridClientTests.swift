import Foundation
import Testing
@testable import GreenCore

@Suite("EIAGridClient")
struct EIAGridClientTests {
    static let now = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17T00:00:00Z

    func client(_ transport: MockTransport) -> EIAGridClient {
        EIAGridClient(retry: .instant(), transport: transport, now: { Self.now }, memo: EIAResponseMemo())
    }

    @Test func historyBuildsTheGridMonitorQuery() async throws {
        let transport = MockTransport([.fixture("eia/grid_monitor_isne.json")])
        _ = try await client(transport).history(zone: "US-NE-ISNE", hours: 168)
        let request = try #require(transport.requests.first)
        #expect(request.url?.host() == "www.eia.gov")
        #expect(request.url?.path() == "/electricity/930-api/region_data_by_fuel_type/series_data")
        #expect(request.queryValue("respondent[0]") == "ISNE")
        #expect(request.queryValue("type[0]") == "NG")
        #expect(request.queryValue("timezone") == "UTC")
        #expect(request.queryValue("start") == "10102026 00:00:00", "7 days before now, as a UTC hour")
        #expect(request.queryValue("end") == "10172026 00:00:00")
    }

    @Test func intensityIsTheGenerationWeightedFactorMean() async throws {
        let transport = MockTransport([.fixture("eia/grid_monitor_isne.json")])
        let points = try await client(transport).history(zone: "US-NE-ISNE", hours: 24)
        #expect(points.count == 3)
        #expect(points.map(\.date) == [1_792_198_800, 1_792_202_400, 1_792_206_000].map { Date(timeIntervalSince1970: $0) })
        // Recorded ISO-NE mix for 2026-10-17 01:00–03:00 UTC; storage (BAT, PS) excluded. Expected values
        // computed by hand from the fixture.
        let expected = [326.8438, 319.7215, 314.1800]
        for (point, value) in zip(points, expected) {
            #expect(abs(point.gramsCO2ePerKWh - value) < 0.001)
            #expect(point.zone == "US-NE-ISNE")
            #expect(!point.isEstimated)
        }
    }

    @Test func latestIsTheNewestPublishedHour() async throws {
        let transport = MockTransport([.fixture("eia/grid_monitor_isne.json")])
        let point = try await client(transport).latest(zone: "US-NE-ISNE")
        #expect(point.date == Date(timeIntervalSince1970: 1_792_206_000))
    }

    @Test func callersShareOneRequest() async throws {
        let transport = MockTransport([.fixture("eia/grid_monitor_isne.json")])
        let client = client(transport)
        let points = try await client.history(zone: "US-NE-ISNE", hours: 168)
        let point = try await client.latest(zone: "US-NE-ISNE")
        #expect(transport.requests.count == 1, "latest reuses the 7-day response")
        #expect(points.count == 3)
        #expect(point.date == Date(timeIntervalSince1970: 1_792_206_000))
    }

    @Test func failuresAreNotReused() async throws {
        let transport = MockTransport([.json("{}", status: 400), .fixture("eia/grid_monitor_isne.json")])
        let client = client(transport)
        await #expect(throws: GreenCoreError.self) { _ = try await client.history(zone: "US-NE-ISNE", hours: 168) }
        let points = try await client.history(zone: "US-NE-ISNE", hours: 168)
        #expect(points.count == 3)
        #expect(transport.requests.count == 2)
    }

    @Test func incompleteHoursAreSkipped() {
        let date = Date(timeIntervalSince1970: 1_792_209_600)
        let rows = [EIAGridClient.Row(date: date, fuel: "NG", megawattHours: 7000),
                    EIAGridClient.Row(date: date, fuel: "BAT", megawattHours: -20)]
        #expect(EIAGridClient.intensities(rows, zone: "US-NE-ISNE").isEmpty)
    }

    @Test func reportingGapsAreSkipped() {
        // Recorded ISO-NE hour 2026-10-14T22Z: gas, nuclear and wind all reported 0, leaving only oil.
        func hour(_ offset: Double, _ mix: [String: Double]) -> [EIAGridClient.Row] {
            let date = Date(timeIntervalSince1970: 1_791_997_200 + offset * 3600)
            return mix.map { EIAGridClient.Row(date: date, fuel: $0.key, megawattHours: $0.value) }
        }
        let normal: [String: Double] = ["NG": 8500, "NUC": 2280, "WND": 500, "WAT": 210]
        let rows = hour(0, normal) + hour(1, normal) + hour(2, ["NG": 0, "NUC": 0, "WND": 0, "OIL": 115, "SNB": 5])
        let points = EIAGridClient.intensities(rows, zone: "US-NE-ISNE")
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.gramsCO2ePerKWh < 400 })
    }

    @Test func nullValuesAreTolerated() throws {
        let json = #"[{"data":[{"FUEL_TYPE_ID":"NG","VALUES":{"DATES":["10/17/2026 01:00:00","10/17/2026 02:00:00"],"DATA":[8446,null]}}]}]"#
        let rows = try JSONDecoder().decode([EIAGridClient.SeriesGroup].self, from: Data(json.utf8)).flatMap(\.rows)
        #expect(rows.map(\.megawattHours) == [8446, nil])
        #expect(rows.first?.date == Date(timeIntervalSince1970: 1_792_198_800))
    }

    @Test func zonesMapToBalancingAuthorities() {
        #expect(EIAGridClient.respondent(forZone: "US-NE-ISNE") == "ISNE")
        #expect(EIAGridClient.respondent(forZone: "US-MIDA-PJM") == "PJM")
        #expect(EIAGridClient.respondent(forZone: "US") == "US48")
        #expect(EIAGridClient.respondent(forZone: "US-HI") == nil)
        #expect(EIAGridClient.respondent(forZone: "DE") == nil)
    }

    @Test func nonUSZonesThrowNotFoundWithoutARequest() async throws {
        let transport = MockTransport([])
        await #expect(throws: GreenCoreError.notFound) {
            _ = try await client(transport).history(zone: "DE", hours: 24)
        }
        #expect(transport.requests.isEmpty)
    }
}
