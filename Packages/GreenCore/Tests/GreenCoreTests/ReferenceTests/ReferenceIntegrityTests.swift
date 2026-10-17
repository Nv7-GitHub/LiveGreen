import Foundation
import Testing
@testable import GreenCore

@Suite("Reference table integrity")
struct ReferenceIntegrityTests {
    let store: ReferenceStore

    init() throws {
        store = try ReferenceStore(bundle: ReferenceStore.resourceBundle)
    }

    @Test func bundledStoreLoads() {
        #expect(!ReferenceStore.bundled.recordInfo.isEmpty)
        #expect(ReferenceStore.bundled.recordInfo.count == store.recordInfo.count)
    }

    @Test func everyRecordIsCited() {
        #expect(store.recordInfo.count > 200)
        for info in store.recordInfo {
            #expect(!info.citation.title.isEmpty, "\(info.table)/\(info.key) has no citation title")
            if let url = info.citation.url {
                #expect(url.scheme == "https", "\(info.table)/\(info.key) citation is not https: \(url)")
            }
        }
    }

    @Test func tableSizesMatchSpec() {
        let counts = Dictionary(grouping: store.recordInfo, by: \.table).mapValues(\.count)
        #expect((counts["food_factors"] ?? 0) >= 40)
        #expect((counts["device_defaults"] ?? 0) >= 40)
        #expect((counts["asus_pcf"] ?? 0) >= 15)
        #expect((counts["fiber_factors"] ?? 0) >= 12)
        #expect((counts["material_endoflife"] ?? 0) >= 20)
        // 27 eGRID subregions + US + ~40 countries + 4 shapes.
        #expect((counts["grid_intensity"] ?? 0) >= 60)
        #expect((counts["per_capita"] ?? 0) >= 30)
    }

    @Test func foodValuesArePositiveAndStagesSumToOne() {
        for info in store.recordInfo where info.table == "food_factors" {
            let factor = try! #require(store.foodFactor(group: info.key))
            #expect(factor.kgCO2ePerKg > 0)
            #expect(factor.litersPerKg >= 0 && factor.landM2YearPerKg > 0 && factor.gPO4ePerKg > 0)
            let total = factor.stageShares.values.reduce(0, +)
            #expect(abs(total - 1) < 0.01, "\(info.key) stage shares sum to \(total)")
            #expect(factor.stageShares.values.allSatisfy { $0 >= 0 })
        }
    }

    @Test func materialsHaveValidRanges() {
        var resinCodes = Set<Int>()
        for info in store.recordInfo where info.table == "material_endoflife" {
            let material = try! #require(store.materialFactor(material: info.key))
            #expect((0...100).contains(material.endOfLife.recyclablePercent))
            #expect(material.endOfLife.decompositionYears > 0)
            #expect(material.kgCO2ePerKg >= 0)
            if let code = material.resinCode {
                #expect((1...7).contains(code))
                #expect(material.endOfLife.isPlastic)
                resinCodes.insert(code)
            }
        }
        #expect(resinCodes == Set(1...7))
    }

    @Test func devicesHaveValidRanges() {
        for info in store.recordInfo where info.table == "device_defaults" {
            let device = try! #require(store.deviceProfile(deviceType: info.key))
            let d = device.defaults
            #expect(d.onWatts > 0 && d.standbyWatts >= 0 && d.lifespanYears > 0 && d.embodiedKgCO2e > 0)
            #expect((0...10).contains(d.repairability))
            #expect((0...24).contains(d.typicalHoursOnPerDay))
            #expect(d.recyclablePercent.map { (0...100).contains($0) } ?? true)
            #expect(abs(d.stageShares.values.reduce(0, +) - 1) < 0.01)
            #expect(d.stageShares[.use] == nil, "\(info.key): embodied split must not include use")
        }
        for load in DeferrableLoadType.allCases {
            let hasDevice = store.recordInfo.contains { info in
                info.table == "device_defaults" && store.deviceProfile(deviceType: info.key)?.deferrableLoad == load
            }
            #expect(hasDevice, "No device type for deferrable load \(load)")
        }
    }

    @Test func gridShapesAreNormalized() {
        for info in store.recordInfo where info.table == "grid_intensity" && !info.key.hasPrefix("shape:") {
            let record = try! #require(store.gridIntensity(region: info.key))
            #expect(record.hourlyShape.count == 24)
            #expect(abs(record.hourlyShape.reduce(0, +) / 24 - 1) < 0.001)
            #expect((10...1600).contains(record.annualAverageGPerKWh), "\(info.key): \(record.annualAverageGPerKWh)")
        }
    }

    @Test func asusStagesSumToOne() {
        for info in store.recordInfo where info.table == "asus_pcf" {
            let detail = try! #require(store.asusDetail(model: info.key))
            #expect(detail.record.totalKgCO2e > 0 && detail.annualKWh > 0)
            #expect(abs(detail.record.stageShares.values.reduce(0, +) - 1) < 0.01)
            #expect(detail.record.citation.tier == .exactRecord)
        }
    }

    @Test func perCapitaBaselinesAreComplete() {
        for info in store.recordInfo where info.table == "per_capita" && info.key.count == 2 {
            let baseline = try! #require(store.perCapita(region: info.key))
            for metric in CohortModel.comparedMetrics {
                #expect((baseline.medians[metric] ?? 0) > 0, "\(info.key) median for \(metric)")
                #expect((baseline.sigmas[metric] ?? 0) > 0)
            }
            #expect(Set(baseline.dietModifiers.keys) == Set(Diet.allCases))
        }
        for metric in CohortModel.comparedMetrics {
            let total = Category.allCases.reduce(0) { $0 + store.cohort.share(of: $1, for: metric) }
            #expect(total > 0 && total < 1, "\(metric) category shares total \(total)")
        }
    }
}
