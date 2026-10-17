import Foundation
import Testing
@testable import GreenCore

@Suite("Impact engine formulas")
struct ImpactEngineFormulaTests {
    @Test func yearlyElectricity() {
        // (30 W × 8 h + 1 W × 16 h) × 365 / 1000 = 93.44 kWh.
        #expect(abs(ImpactEngine.yearlyElectricity(powerOnW: 30, hoursOnPerDay: 8, standbyW: 1, standbyHoursPerDay: 16) - 93.44) < 1e-9)
        #expect(ImpactEngine.yearlyElectricity(powerOnW: 0, hoursOnPerDay: 24, standbyW: 0, standbyHoursPerDay: 0) == 0)
    }

    @Test func chargingElectricity() {
        // 0.5 kWh × 3/week × 52 ÷ 0.85.
        #expect(abs(ImpactEngine.chargingElectricity(batteryKWh: 0.5, chargesPerWeek: 3) - 78 / 0.85) < 1e-9)
    }

    @Test func carbonFormulas() {
        #expect(ImpactEngine.useCarbon(kWh: 100, gramsPerKWh: 250) == 25)
        #expect(ImpactEngine.yearlyCarbon(embodiedKg: 200, lifespanYears: 4, annualUseKg: 25) == 75)
        #expect(ImpactEngine.lifetimeCarbon(embodiedKg: 200, lifespanYears: 4, annualUseKg: 25) == 300)
        // Yearly = lifetime ÷ lifespan.
        #expect(ImpactEngine.lifetimeCarbon(embodiedKg: 200, lifespanYears: 4, annualUseKg: 25) / 4
                == ImpactEngine.yearlyCarbon(embodiedKg: 200, lifespanYears: 4, annualUseKg: 25))
    }

    @Test func foodYearly() {
        // Beef 99.48 kg/kg × 0.12 kg × 2/week × 52.
        #expect(abs(ImpactEngine.foodYearly(perKg: 99.48, servingKg: 0.12, servingsPerWeek: 2) - 1241.5104) < 1e-9)
    }

    @Test func gridForProfile() {
        let engine = ImpactEngine()
        #expect(abs(engine.gridGramsPerKWh(for: .default) - 246.4) < 0.01) // default profile is ISO-NE
        let unknown = UserProfile(region: Region(countryCode: "ZZ"))
        #expect(engine.gridGramsPerKWh(for: unknown) == ReferenceStore.bundled.gridIntensity(region: "US")?.annualAverageGPerKWh)
    }
}

@Suite("Impact engine annualization")
struct ImpactEngineAnnualTests {
    let engine = ImpactEngine()

    func exact(_ value: Double, _ metric: MetricKey) -> Measured { .exact(value, unit: metric.unit, tier: .exactRecord) }

    @Test func durablesDivideByLifespan() throws {
        var laptop = Component(name: "Laptop", category: .electronic)
        laptop.metrics = [.carbon: exact(400, .carbon), .lifespan: exact(4, .lifespan), .yearlyElectricity: exact(60, .yearlyElectricity)]
        let yearly = engine.annualized(laptop)
        #expect(try #require(yearly[.carbon]).value == 100)
        #expect(try #require(yearly[.carbon]).low == 100) // exact inputs stay exact
        #expect(try #require(yearly[.yearlyElectricity]).value == 60)
        let views = try #require(engine.carbonViews(of: laptop))
        #expect(views.lifetime?.value == 400 && views.perYear.value == 100)
    }

    @Test func consumablesMultiplyByFrequency() throws {
        var burger = Component(name: "Burger", category: .food, usage: UsageProfile(servingsPerWeek: 3))
        burger.metrics = [.carbon: exact(2, .carbon), .water: exact(10, .water)]
        #expect(try #require(engine.yearly(.carbon, of: burger)).value == 312)
        var cup = Component(name: "Cup", category: .packaging, usage: UsageProfile(usesPerWeek: 5))
        cup.metrics = [.carbon: exact(0.1, .carbon)]
        #expect(abs(try #require(engine.yearly(.carbon, of: cup)).value - 26) < 1e-9)
        let views = try #require(engine.carbonViews(of: cup))
        #expect(views.lifetime == nil)
    }

    @Test func totalsAreDeterministicAndCoverRange() throws {
        let scan = SampleScansForTests.desk
        let first = engine.yearlyTotals(scan.components, seed: scan.seed)
        let second = engine.yearlyTotals(scan.components, seed: scan.seed)
        #expect(first == second)
        let carbon = try #require(first[.carbon])
        let pointSum = scan.components.compactMap { engine.yearly(.carbon, of: $0)?.value }.reduce(0, +)
        #expect(abs(carbon.value - pointSum) < 1e-6)
        #expect(carbon.low < carbon.value && carbon.value < carbon.high)
        let items = engine.itemTotals(scan.components, seed: scan.seed)
        #expect(abs(try #require(items[.carbon]).value - scan.components.compactMap { $0.metrics[.carbon]?.value }.reduce(0, +)) < 1e-6)
    }

    @Test func stageBreakdownUsesRecordedOrDefaultShares() throws {
        var monitor = Component(name: "Monitor", category: .electronic, stageShares: [.manufacturing: 3, .use: 1])
        monitor.metrics[.carbon] = Measured(value: 400, low: 300, high: 500, unit: .kgCO2e, tier: .factorModel)
        let stages = engine.stageBreakdown(monitor)
        #expect(try #require(stages[.manufacturing]).value == 300)
        #expect(try #require(stages[.use]).high == 125)
        monitor.stageShares = [:]
        let defaults = engine.stageShares(for: monitor)
        #expect(abs(defaults.values.reduce(0, +) - 1) < 1e-9)
        #expect(engine.stageShares(for: monitor, metric: .yearlyElectricity) == [.use: 1])
        #expect(engine.stageShares(for: monitor, metric: .repairability).isEmpty)
    }

    @Test func answeringHoursRederivesElectricityAndCarbon() throws {
        var monitor = Component(name: "Monitor", category: .electronic, quantities: Quantities(deviceType: "monitor"),
                                usage: UsageProfile(hoursOnPerDay: 8, standbyHoursPerDay: 16))
        monitor.metrics = [.powerOn: exact(20, .powerOn), .standbyPower: exact(0.5, .standbyPower), .lifespan: exact(6, .lifespan),
                           .carbon: Measured(value: 500, low: 400, high: 600, unit: .kgCO2e, tier: .factorModel)]
        monitor.metrics[.yearlyElectricity] = try #require(engine.derivedYearlyElectricity(for: monitor))
        let before = try #require(monitor.metrics[.yearlyElectricity]).value
        #expect(abs(before - (20 * 8 + 0.5 * 16) * 365 / 1000) < 1e-9)

        let option = AnswerOption(label: "~2 h", field: .hoursOnPerDay, value: 2)
        let updated = engine.applyingAnswer(option, to: monitor, profile: .default)
        let after = try #require(updated.metrics[.yearlyElectricity]).value
        #expect(abs(after - (20 * 2 + 0.5 * 16) * 365 / 1000) < 1e-9)
        let expectedDelta = (after - before) * 246.4 / 1000 * 6
        #expect(abs(try #require(updated.metrics[.carbon]).value - (500 + expectedDelta)) < 1e-6)
        #expect(updated.usage?.hoursOnPerDay == 2)
        #expect(abs(updated.stageShares.values.reduce(0, +) - 1) < 1e-9)
    }

    @Test func batteryLoadsUseCharges() throws {
        let bike = Component(name: "E-bike", category: .electronic, quantities: Quantities(deviceType: "ebike"),
                             usage: UsageProfile(chargesPerWeek: 3))
        let kWh = try #require(engine.derivedYearlyElectricity(for: bike))
        #expect(abs(kWh.value - 0.5 * 3 * 52 / 0.85) < 1e-9)
    }
}

/// Small fixtures shared by engine tests.
enum SampleScansForTests {
    static let desk: ScanResult = {
        let id = UUID(uuidString: "6B1E5A52-6F7B-4C25-9C3F-1D3E2B8A9C10")!
        var laptop = Component(name: "Laptop", category: .electronic)
        laptop.metrics = [.carbon: Measured(value: 230, low: 194, high: 266, unit: .kgCO2e, tier: .exactRecord),
                          .lifespan: .exact(4, unit: .years, tier: .exactRecord)]
        var burger = Component(name: "Burger", category: .food, usage: UsageProfile(servingsPerWeek: 2))
        burger.metrics = [.carbon: Measured(value: 11.9, low: 7.5, high: 19, unit: .kgCO2e, tier: .factorModel)]
        var cup = Component(name: "Cup", category: .packaging, usage: UsageProfile(usesPerWeek: 5))
        cup.metrics = [.carbon: Measured(value: 0.02, low: 0.01, high: 0.04, unit: .kgCO2e, tier: .factorModel)]
        return ScanResult(id: id, date: Date(timeIntervalSince1970: 1_790_000_000), title: "Desk", components: [laptop, burger, cup])
    }()
}
