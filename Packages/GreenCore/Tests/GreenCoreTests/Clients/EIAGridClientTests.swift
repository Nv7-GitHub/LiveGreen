import Foundation
import Testing
@testable import GreenCore

@Suite("EIAGridClient")
struct EIAGridClientTests {
    static let now = Date(timeIntervalSince1970: 1_792_195_200) // 2026-10-17T00:00:00Z

    func client(_ transport: MockTransport, key: String? = "eia-key") -> EIAGridClient {
        EIAGridClient(apiKey: key, retry: .instant(), transport: transport, now: { Self.now }, memo: EIAResponseMemo())
    }

    @Test func historyBuildsTheFuelMixQuery() async throws {
        let transport = MockTransport([.fixture("eia/fuel_mix_isne.json")])
        _ = try await client(transport).history(zone: "US-NE-ISNE", hours: 168)
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/v2/electricity/rto/fuel-type-data/data/")
        #expect(request.queryValue("api_key") == "eia-key")
        #expect(request.queryValue("frequency") == "hourly")
        #expect(request.queryValue("facets[respondent][]") == "ISNE")
        #expect(request.queryValue("start") == "2026-10-10T00", "7 days before now, as a UTC hour")
    }

    @Test func intensityIsTheGenerationWeightedFactorMean() async throws {
        let transport = MockTransport([.fixture("eia/fuel_mix_isne.json")])
        let points = try await client(transport).history(zone: "US-NE-ISNE", hours: 24)
        #expect(points.count == 3)
        #expect(points.map(\.date) == [1_792_198_800, 1_792_202_400, 1_792_206_000].map { Date(timeIntervalSince1970: $0) })
        // Recorded ISO-NE mix; storage (BAT, PS) excluded. Expected values computed by hand from the fixture.
        let expected = [326.8438, 319.7215, 314.1800]
        for (point, value) in zip(points, expected) {
            #expect(abs(point.gramsCO2ePerKWh - value) < 0.001)
            #expect(point.zone == "US-NE-ISNE")
            #expect(!point.isEstimated)
        }
    }

    @Test func latestIsTheNewestPublishedHour() async throws {
        let transport = MockTransport([.fixture("eia/fuel_mix_isne.json")])
        let point = try await client(transport).latest(zone: "US-NE-ISNE")
        #expect(point.date == Date(timeIntervalSince1970: 1_792_206_000))
    }

    @Test func callersShareOneRequest() async throws {
        let transport = MockTransport([.fixture("eia/fuel_mix_isne.json")])
        let client = client(transport)
        let points = try await client.history(zone: "US-NE-ISNE", hours: 168)
        let point = try await client.latest(zone: "US-NE-ISNE")
        #expect(transport.requests.count == 1, "latest reuses the 7-day response")
        #expect(points.count == 3)
        #expect(point.date == Date(timeIntervalSince1970: 1_792_206_000))
    }

    @Test func failuresAreNotReused() async throws {
        let transport = MockTransport([.json("{}", status: 400), .fixture("eia/fuel_mix_isne.json")])
        let client = client(transport)
        await #expect(throws: GreenCoreError.self) { _ = try await client.history(zone: "US-NE-ISNE", hours: 168) }
        let points = try await client.history(zone: "US-NE-ISNE", hours: 168)
        #expect(points.count == 3)
        #expect(transport.requests.count == 2)
    }

    @Test func incompleteHoursAreSkipped() {
        let rows = [EIAGridClient.Row(period: "2026-10-17T04", fueltype: "NG", value: "7000"),
                    EIAGridClient.Row(period: "2026-10-17T04", fueltype: "BAT", value: "-20")]
        #expect(EIAGridClient.intensities(rows, zone: "US-NE-ISNE").isEmpty)
    }

    @Test func reportingGapsAreSkipped() {
        // Recorded ISO-NE hour 2026-10-14T22: gas, nuclear and wind all reported 0, leaving only oil.
        func hour(_ h: Int, _ mix: [String: String]) -> [EIAGridClient.Row] {
            mix.map { EIAGridClient.Row(period: "2026-10-14T\(h)", fueltype: $0.key, value: $0.value) }
        }
        let normal = ["NG": "8500", "NUC": "2280", "WND": "500", "WAT": "210"]
        let rows = hour(20, normal) + hour(21, normal)
            + hour(22, ["NG": "0", "NUC": "0", "WND": "0", "OIL": "115", "SNB": "5"])
        let points = EIAGridClient.intensities(rows, zone: "US-NE-ISNE")
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.gramsCO2ePerKWh < 400 })
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

    @Test func missingKeyThrows() async throws {
        await #expect(throws: GreenCoreError.missingAPIKey("EIA_API_KEY")) {
            _ = try await client(MockTransport([]), key: nil).latest(zone: "US-NE-ISNE")
        }
    }
}
