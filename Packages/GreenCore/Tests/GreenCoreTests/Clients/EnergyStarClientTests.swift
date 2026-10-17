import Foundation
import Testing
@testable import GreenCore

@Suite("EnergyStarClient")
struct EnergyStarClientTests {
    /// Serves the recorded Dell displays query for the displays dataset and `[]` for every other one.
    static func transport() -> MockTransport {
        MockTransport(route: { request in
            request.url?.path() == "/resource/qbg3-d468.json"
                ? .fixture("energystar/displays_dell_e2225h.json") : .json("[]")
        })
    }

    @Test func buildsSoQLQuery() async throws {
        let transport = Self.transport()
        let client = EnergyStarClient(appToken: "app-token", retry: .instant(), transport: transport)
        _ = try await client.appliance(brand: "Dell Technologies", model: "E2225H", deviceType: "monitor")

        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1, "device type narrows to the displays dataset")
        #expect(request.url?.host() == "data.energystar.gov")
        #expect(request.value(forHTTPHeaderField: "X-App-Token") == "app-token")
        let whereClause = try #require(request.queryValue("$where"))
        #expect(whereClause.hasPrefix("upper(brand_name) like '%DELL%' AND ("))
        #expect(whereClause.contains("upper(model_number) like '%E%2%2%2%'"))
        #expect(whereClause.contains("upper(additional_model_information) like '%E%2%2%2%'"))
        #expect(request.queryValue("$order") == "pd_id")
        #expect(request.queryValue("$limit") == "50")
    }

    @Test func picksExactModelAcrossAllDatasets() async throws {
        let transport = Self.transport()
        let client = EnergyStarClient(retry: .instant(), transport: transport)
        let record = try #require(try await client.appliance(brand: "Dell", model: "E2225H"))

        #expect(transport.requests.count == EnergyStarDataset.all.count)
        #expect(record.brand == "DELL")
        #expect(record.model == "E2225Ht")
        #expect(record.productType == "Monitors")
        #expect(record.onModeWatts == 10.94)
        #expect(record.standbyWatts == 0.17)
        #expect(record.annualKWh == nil)
        #expect(record.datasetName == "ENERGY STAR Certified Displays")
        #expect(record.sourceURL.query()?.contains("pd_id=") == true)

        let metrics = record.measuredMetrics
        #expect(metrics[.powerOn]?.tier == .exactRecord)
        #expect(metrics[.powerOn]?.value == 10.94)
        #expect(metrics[.yearlyElectricity] == nil)
    }

    @Test func noMatchIsNil() async throws {
        let client = EnergyStarClient(retry: .instant(), transport: Self.transport())
        #expect(try await client.appliance(brand: "Dell", model: "U3423WE", deviceType: "monitor") == nil)
    }

    @Test func throwsOnlyWhenEveryDatasetFails() async throws {
        let failing = MockTransport(route: { _ in .json("{\"message\":\"down\"}", status: 503) })
        let client = EnergyStarClient(datasets: [.displays, .televisions], retry: .instant(maxAttempts: 1), transport: failing)
        await #expect(throws: GreenCoreError.self) {
            _ = try await client.appliance(brand: "Dell", model: "E2225H")
        }

        let partial = MockTransport(route: { request in
            request.url?.path() == "/resource/qbg3-d468.json" ? .fixture("energystar/displays_dell_e2225h.json")
                : .json("{}", status: 503)
        })
        let tolerant = EnergyStarClient(datasets: [.displays, .televisions], retry: .instant(maxAttempts: 1), transport: partial)
        #expect(try await tolerant.appliance(brand: "Dell", model: "E2225H")?.model == "E2225Ht")
    }

    @Test func escapesPlusAndQuotes() throws {
        let client = EnergyStarClient(transport: MockTransport([]))
        let request = try #require(client.request(for: .roomAirConditioners, brandKey: "BLACK+DECKER'S", model: "BD08NWES"))
        #expect(request.url?.absoluteString.contains("%2B") == true)
        #expect(request.queryValue("$where")?.contains("BLACK+DECKER''S") == true)
    }

    @Test func modelMatching() {
        typealias M = ModelNumberMatcher
        #expect(M.score(query: "E2225H", candidate: "E2225H") == .exact)
        #expect(M.score(query: "ns-32f202na27", candidate: "NS32F202NA27") == .exact)
        #expect(M.score(query: "DLGX3371W", candidate: "DLGX3371*") == .wildcard)
        #expect(M.score(query: "AREF1812", candidate: "AREF18**") == .wildcard)
        #expect(M.score(query: "E2225H", candidate: "E2225Hf") == .variant)
        #expect(M.score(query: "E2225H", candidate: "SE2225H") == .none)
        #expect(M.score(query: "E2225H", candidate: "E2226H") == .none)
        #expect(M.bestScore(query: "QN65QN92DAF", candidates: ["QN65QN90DAF", "QN65QN90DDF,QN65QN90DDF; QN65QN92DAF,QN65QN92DAF"]) == .exact)
        #expect(M.likePattern(for: "S2721H") == "%S%2%7%2%")
        #expect(M.likePattern(for: "AB") == nil)
    }

    @Test func datasetsForDeviceType() {
        #expect(EnergyStarDataset.datasets(forDeviceType: "television") == [.televisions])
        #expect(EnergyStarDataset.datasets(forDeviceType: "laptop") == [.computers])
        #expect(EnergyStarDataset.datasets(forDeviceType: "ebike_charger").count == EnergyStarDataset.all.count)
        #expect(Set(EnergyStarDataset.all.map(\.id)).count == EnergyStarDataset.all.count)
    }
}
