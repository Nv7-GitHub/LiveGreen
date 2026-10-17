import Foundation
import Testing
@testable import GreenCore

@Suite("Reference lookups")
struct ReferenceLookupTests {
    let store = ReferenceStore.bundled

    @Test func foodLookupUsesKeysAliasesAndTokens() throws {
        #expect(try #require(store.foodFactor(group: "beef")).kgCO2ePerKg == 99.48)
        #expect(store.foodFactor(group: "Beef Burger")?.group == "beef")
        #expect(store.foodFactor(group: "chicken")?.group == "poultry")
        #expect(store.foodFactor(group: "French fries")?.group == "potatoes")
        #expect(store.foodFactor(group: "soy milk")?.group == "soy_milk")
        #expect(store.foodFactor(group: "spaceship") == nil)
    }

    @Test func longestAliasWins() {
        #expect(store.fiberFactor(material: "organic cotton")?.material == "organic_cotton")
        #expect(store.fiberFactor(material: "Cotton")?.material == "cotton")
        #expect(store.fiberFactor(material: "recycled polyester")?.material == "recycled_polyester")
    }

    @Test func materialsByNameAndResinCode() {
        #expect(store.endOfLife(material: "PET")?.isPlastic == true)
        #expect(store.endOfLife(material: "aluminum can")?.recyclablePercent == 50.4)
        #expect(store.materialFactor(resinCode: 2)?.endOfLife.material == "hdpe")
        #expect(store.materialFactor(resinCode: 6)?.endOfLife.material == "ps")
    }

    @Test func deviceLookup() {
        #expect(store.deviceDefaults(deviceType: "laptop")?.lifespanYears == 4)
        #expect(store.deviceProfile(deviceType: "e-bike charger")?.deferrableLoad == .eBike)
        #expect(store.deviceProfile(deviceType: "led_lamp")?.defaults.onWatts == 8)
        #expect(store.deviceProfile(deviceType: "washing machine")?.deferrableLoad == .washer)
    }

    @Test func gridLookupBySubregionZoneStateAndCountry() throws {
        // eGRID2023 NEWE: 543.2 lb/MWh × 0.4536 = 246.4 g/kWh.
        #expect(try #require(store.gridIntensity(region: "NEWE")).annualAverageGPerKWh == 246.4)
        #expect(store.gridIntensity(region: "US-NE-ISNE")?.region == "NEWE")
        #expect(store.gridIntensity(region: "US-TX")?.region == "ERCT")
        #expect(store.gridIntensity(region: "FR")?.region == "FR")
        #expect(try #require(store.gridIntensity(region: "FR")).annualAverageGPerKWh < 100)
    }

    @Test func regionResolutionFromZIP() {
        #expect(store.usState(forZIP: "02138") == "MA")
        #expect(store.usState(forZIP: "94103") == "CA")
        #expect(store.usState(forZIP: "10001-1234") == "NY")
        #expect(store.gridSubregion(forZIP: "10001") == "NYCW")
        #expect(store.gridSubregion(forZIP: "14850") == "NYUP")
        #expect(store.gridSubregion(forZIP: "15213") == "RFCW")
        #expect(store.usState(forZIP: "123") == nil)
        let cambridge = Region(countryCode: "US", postalCode: "02138")
        #expect(store.gridIntensity(for: cambridge)?.region == "NEWE")
        #expect(store.gridIntensity(for: Region(countryCode: "SE"))?.region == "SE")
        #expect(store.gridIntensity(for: Region(countryCode: "ZZ"))?.region == "US")
    }

    @Test func perCapitaForCountriesAndStates() throws {
        let us = try #require(store.perCapita(region: "US"))
        let ma = try #require(store.perCapita(region: "US-MA"))
        let wy = try #require(store.perCapita(for: Region(countryCode: "US", usState: "WY")))
        let usCarbon = try #require(us.medians[.carbon])
        // Median = mean × exp(−σ²/2): 17,527 kg × exp(−0.18).
        #expect(abs(usCarbon - 17_527 * exp(-0.18)) < 1)
        #expect(ma.medians[.carbon]! < usCarbon)
        // Production-heavy states are clamped to 1.6× the US.
        #expect(abs(wy.medians[.carbon]! - usCarbon * 1.6) < 0.01)
        #expect(store.perCapita(region: "CA")?.region == "CA") // Canada, not California
        #expect(store.perCapita(for: Region(countryCode: "US", postalCode: "94103"))?.region == "US-CA")
    }

    @Test func asusFuzzyModelMatch() {
        #expect(store.asusPCF(model: "UX3405M")?.totalKgCO2e == 210)
        #expect(store.asusPCF(model: "UX3405MA")?.model == "UX3405M")
        #expect(store.asusPCF(model: "ux3405ma-db71")?.model == "UX3405M")
        #expect(store.asusPCF(model: "VA27UQSB")?.productType == "Monitor")
        #expect(store.asusPCF(model: "UX9")?.model == nil)
        #expect(store.asusPCF(model: "S2721H") == nil)
    }

    @Test func keyNormalization() {
        #expect(ReferenceKey.normalize("  E-Bike Charger! ") == "e_bike_charger")
        #expect(ReferenceKey.normalize("Café crème") == "cafe_creme")
        #expect(ReferenceKey.modelKey("ux3405ma-db71") == "UX3405MADB71")
    }
}
