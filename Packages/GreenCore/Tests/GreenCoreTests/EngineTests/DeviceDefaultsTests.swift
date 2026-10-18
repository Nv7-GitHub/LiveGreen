import Foundation
import Testing
@testable import GreenCore

/// Device-table fixes: a camera row and plastic from the item's own materials (D5), a size-scaled laptop draw (D6),
/// seasonal air conditioning and small-electronics recycling (D7).
@Suite("Device defaults")
struct DeviceDefaultsTests {
    let store = ReferenceStore.bundled
    let resolver = FactorModelResolver(store: .bundled)

    func electronic(_ name: String, _ type: String, kg: Double? = nil, inches: Double? = nil,
                    materials: [MaterialShare] = [], usage: UsageProfile? = nil) -> ResolverOutput {
        resolver.electronic(Component(name: name, category: .electronic, identifiers: Identifiers(materials: materials),
                                      quantities: Quantities(massKg: kg, screenSizeInches: inches, deviceType: type),
                                      usage: usage), profile: .default)
    }

    @Test func aCameraIsNotATablet() throws {
        let camera = store.deviceProfile(deviceType: "mirrorless camera")
        #expect(camera?.defaults.deviceType == "camera")
        let output = electronic("Camera with flip-out screen", "camera", kg: 0.8, inches: 3.5,
                                materials: [MaterialShare(material: "aluminium", percent: 40),
                                            MaterialShare(material: "other_plastic", percent: 30),
                                            MaterialShare(material: "glass", percent: 10),
                                            MaterialShare(material: "electronics_mixed", percent: 20)])
        // Its own materials: 30% of 0.8 kg is plastic, not an iPad's 30 g.
        #expect(abs(try #require(output.metrics[.plasticMass]).value - 240) < 1e-9)
        #expect(try #require(output.metrics[.recyclablePercent]).value == 20)
        #expect(try #require(output.metrics[.lifespan]).value == 6)
        #expect(!(output.metrics[.carbon]?.sources ?? []).contains { $0.title.hasPrefix("Apple") })
        // Without materials, the row's typical plastic stands.
        #expect(try #require(electronic("Camera", "camera").metrics[.plasticMass]).value == 200)
    }

    @Test func smallElectronicsRecycleAtEWasteRates() {
        for type in ["smartphone", "tablet", "smartwatch", "headphones", "phone_charger", "camera"] {
            let rate = store.deviceProfile(deviceType: type)?.defaults.recyclablePercent ?? 100
            #expect(rate <= 20, "\(type): \(rate)%")
        }
        // Large appliances are scrapped for their metal and keep their higher rates.
        #expect((store.deviceProfile(deviceType: "refrigerator")?.defaults.recyclablePercent ?? 0) >= 70)
    }

    @Test func laptopDrawIsLowerAndScalesWithTheScreen() throws {
        let usage = UsageProfile(hoursOnPerDay: 5, standbyHoursPerDay: 19)
        let air = electronic("MacBook Air 13", "laptop", inches: 13.6, usage: usage)
        let pro = electronic("MacBook Pro 16", "laptop", inches: 16.2, usage: usage)
        let airWatts = try #require(air.metrics[.powerOn]).value
        #expect(airWatts < 10 && airWatts > 7, "\(airWatts) W")
        #expect(try #require(pro.metrics[.powerOn]).value > airWatts)
        let airKWh = try #require(air.metrics[.yearlyElectricity]).value
        #expect(airKWh < 22, "\(airKWh) kWh/yr, was ~37 at 20 W")
        #expect(try #require(pro.metrics[.yearlyElectricity]).value > airKWh)
        // A gaming laptop is its own row.
        #expect((store.deviceProfile(deviceType: "gaming laptop")?.defaults.onWatts ?? 0) > 30)
    }

    @Test func anAirConditionerRunsOnlyInSummer() throws {
        let ac = try #require(store.deviceProfile(deviceType: "window ac"))
        #expect(ac.activeDaysPerYear == 100)
        let output = electronic("Window air conditioner", "air_conditioner")
        let kWh = try #require(output.metrics[.yearlyElectricity]).value
        let expected = (800.0 * 6 + 1 * 18) * 100 / 1000
        #expect(abs(kWh - expected) < 1e-9, "\(kWh)")
        // A year-round device still counts every day.
        #expect(ImpactEngine.yearlyElectricity(powerOnW: 10, hoursOnPerDay: 1, standbyW: 0, standbyHoursPerDay: 0)
            == 10.0 * 365 / 1000)
    }
}
