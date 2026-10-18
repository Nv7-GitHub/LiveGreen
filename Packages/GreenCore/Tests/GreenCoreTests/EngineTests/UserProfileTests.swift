import Foundation
import Testing
@testable import GreenCore

@Suite("User profile answers")
struct UserProfileTests {
    /// A profile saved by the multi-mode build: walk, bike and work from home are dropped (they emitted
    /// nothing), no heating becomes an empty set, and the old diet and clothing answers keep their footprint.
    @Test func multiModeProfilesFromTheLastBuildDecode() throws {
        let json = #"""
            {"region":{"countryCode":"US","usState":"NY"},"householdSize":2,"diet":"flexitarian",
             "commuteKmPerWeekByMode":["car",80,"bike",30,"remote",0,"walk",5],"homeType":"townhouse",
             "heating":"none","clothingHabit":"mostlySecondHand","chargingItems":["laptopCharger"],
             "onboardingCompleted":true}
            """#
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        #expect(profile.commuteKmPerWeekByMode == [.car: 80])
        #expect(profile.heatingSources.isEmpty)
        #expect(profile.diet == .flexitarian)
        #expect(profile.chargingItems == [.laptopCharger])
        let model = try #require(CohortModel(profile: profile, store: .bundled))
        // Close to the old modifiers: flexitarian 0.83, mostly second-hand 0.6, unheated 0.9.
        #expect(abs(model.modifier(for: .food) - 0.83) < 0.01)
        #expect(abs(model.modifier(for: .clothing) - 0.6) < 0.01)
        #expect(model.heatingModifier == 0.9)

        let walkOnly = try JSONDecoder().decode(UserProfile.self, from: Data(#"""
            {"region":{"countryCode":"US"},"householdSize":1,"diet":"omnivore","commuteKmPerWeekByMode":["walk",20],
             "homeType":"dorm","heating":"districtHeating","clothingHabit":"mostlyNew","chargingItems":[],
             "onboardingCompleted":false}
            """#.utf8))
        #expect(walkOnly.commuteKmPerWeekByMode.isEmpty && walkOnly.commuteMode == nil)
        #expect(walkOnly.newClothesPerYear == 83)

        // The current format round-trips, heating sources included.
        var current = profile
        current.heatingSources = [.heatPump, .naturalGas]
        current.floorAreaM2 = 120
        current.commuteKmPerWeekByMode = [.transit: 40, .eBike: 25]
        #expect(try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(current)) == current)
    }

    @Test func dietIsDerivedFromMealCounts() {
        #expect(UserProfile(meatMealsPerWeek: 0, dairyMealsPerWeek: 0).diet == .vegan)
        #expect(UserProfile(meatMealsPerWeek: 0, dairyMealsPerWeek: 3).diet == .vegetarian)
        #expect(UserProfile(meatMealsPerWeek: 6).diet == .flexitarian)
        #expect(UserProfile(meatMealsPerWeek: 7).diet == .omnivore)
        #expect(UserProfile(meatMealsPerWeek: 40, dairyMealsPerWeek: -2).meatMealsPerWeek == 21)
        #expect(UserProfile(dairyMealsPerWeek: -2).dairyMealsPerWeek == 0)
        for diet in Diet.allCases {
            let meals = diet.typicalMealsPerWeek
            #expect(UserProfile(meatMealsPerWeek: meals.meat, dairyMealsPerWeek: meals.dairy).diet == diet)
        }
    }

    /// Profiles saved with a diet label keep about the food footprint its old modifier gave.
    @Test func legacyDietsKeepTheirFoodFootprint() throws {
        let old: [Diet: Double] = [.omnivore: 1, .flexitarian: 0.83, .vegetarian: 0.68, .vegan: 0.51]
        for (diet, modifier) in old {
            let meals = diet.typicalMealsPerWeek
            let profile = UserProfile(meatMealsPerWeek: meals.meat, dairyMealsPerWeek: meals.dairy)
            let model = try #require(CohortModel(profile: profile, store: .bundled))
            #expect(abs(model.modifier(for: .food) - modifier) < 0.005, "\(diet) \(model.modifier(for: .food))")
        }
    }

    @Test func promptSummaryDescribesTheAnswers() {
        let profile = UserProfile(meatMealsPerWeek: 3, dairyMealsPerWeek: 12, commuteKmPerWeekByMode: [:],
                                  homeType: .detachedHouse, floorAreaM2: 180, heatingSources: [.heatPump, .naturalGas],
                                  newClothesPerYear: 20)
        let summary = profile.promptSummary
        #expect(summary.contains("meat in ~3 and dairy in ~12 of 21 meals a week (flexitarian)"))
        #expect(summary.contains("no regular travel by car or transit"))
        #expect(summary.contains("detachedHouse of ~180 m² heated by naturalGas and heatPump"))
        #expect(summary.contains("~20 new clothing items a year"))
        #expect(UserProfile(heatingSources: []).promptSummary.contains("apartment with no heating"))
    }
}

@Suite("Profile modifiers")
struct ProfileModifierTests {
    let store = ReferenceStore.bundled

    func model(_ profile: UserProfile) throws -> CohortModel { try #require(CohortModel(profile: profile, store: store)) }

    @Test func typicalAnswersGiveTheAverage() throws {
        let typical = try model(.default)
        for metric in [MetricKey.carbon, .land, .water] {
            #expect(abs(typical.modifier(for: .food, metric: metric) - 1) < 1e-9)
        }
        #expect(abs(typical.modifier(for: .clothing) - 1) < 1e-9)
    }

    @Test func mealCountsDriveFood() throws {
        let vegan = try model(UserProfile(meatMealsPerWeek: 0, dairyMealsPerWeek: 0))
        #expect(abs(vegan.modifier(for: .food) - 0.51) < 1e-9)
        // Plant-based diets cut land use far more than carbon, and water less.
        #expect(abs(vegan.modifier(for: .food, metric: .land) - 0.24) < 1e-9)
        #expect(abs(vegan.modifier(for: .food, metric: .water) - 0.81) < 1e-9)
        // Linear in meals: a meat meal weighs four dairy meals (1.8 vs 0.45 kg CO2e).
        let meat = try model(UserProfile(meatMealsPerWeek: 1, dairyMealsPerWeek: 0)).modifier(for: .food) - 0.51
        let dairy = try model(UserProfile(meatMealsPerWeek: 0, dairyMealsPerWeek: 1)).modifier(for: .food) - 0.51
        #expect(abs(meat / dairy - 4) < 1e-9)
        let everyMeal = try model(UserProfile(meatMealsPerWeek: 21, dairyMealsPerWeek: 21))
        #expect(everyMeal.modifier(for: .food) > 1.5)
        let estimate = { (meat: Int) in LifestyleEstimate(profile: UserProfile(meatMealsPerWeek: meat)).kgPerYear[.food] ?? 0 }
        #expect(estimate(14) > estimate(9) && estimate(9) > estimate(2))
    }

    @Test func clothingScalesWithNewItems() throws {
        #expect(abs(try model(UserProfile(newClothesPerYear: 0)).modifier(for: .clothing) - 0.15) < 1e-9)
        #expect(abs(try model(UserProfile(newClothesPerYear: 128)).modifier(for: .clothing) - 1.85) < 1e-9)
    }

    @Test func floorAreaScalesHomeEnergyAgainstTheTypicalHome() throws {
        let typicalArea = try #require(store.cohort.homeSize.typicalFloorAreaM2[.detachedHouse])
        #expect(abs(typicalArea - 2_264 / 10.763_9) < 0.1, "RECS 2020 detached average, 2,264 ft²")
        let unanswered = try model(UserProfile(householdSize: 1, homeType: .detachedHouse))
        let typical = try model(UserProfile(householdSize: 1, homeType: .detachedHouse, floorAreaM2: typicalArea))
        let double = try model(UserProfile(householdSize: 1, homeType: .detachedHouse, floorAreaM2: typicalArea * 2))
        let small = try model(UserProfile(householdSize: 1, homeType: .detachedHouse, floorAreaM2: typicalArea / 2))
        for metric in [MetricKey.carbon, .yearlyElectricity] {
            let base = unanswered.modifier(for: .household, metric: metric)
            #expect(abs(typical.modifier(for: .household, metric: metric) - base) < 1e-9)
            // Heating and cooling (52% of household energy) double with the area; the rest stays.
            #expect(abs(double.modifier(for: .household, metric: metric) / base - 1.52) < 1e-9)
            #expect(abs(small.modifier(for: .household, metric: metric) / base - 0.74) < 1e-9)
        }
        #expect(double.modifier(for: .food) == unanswered.modifier(for: .food))
        let homeEnergy = { (area: Double) in
            LifestyleEstimate(profile: UserProfile(homeType: .detachedHouse, floorAreaM2: area)).kgPerYear[.homeEnergy] ?? 0
        }
        #expect(homeEnergy(300) > homeEnergy(200) && homeEnergy(200) > homeEnergy(100))
        // Clamped: a stray answer cannot scale home energy without bound.
        let huge = try model(UserProfile(householdSize: 1, homeType: .apartment, floorAreaM2: 100_000))
        #expect(huge.modifier(for: .household) / (try model(UserProfile(householdSize: 1)).modifier(for: .household)) <= 3.08 + 1e-9)
    }

    @Test func heatingSourcesAverageEvenly() throws {
        let modifiers = store.cohort.heatingModifiers
        let mixed = try model(UserProfile(heatingSources: [.naturalGas, .heatPump]))
        #expect(abs(mixed.heatingModifier - (modifiers[.naturalGas]! + modifiers[.heatPump]!) / 2) < 1e-12)
        #expect(try model(UserProfile(heatingSources: [])).heatingModifier == modifiers[.none])
        #expect(try model(UserProfile(heatingSources: [.none, .oil])).heatingModifier == modifiers[.oil])
        let carbon = store.cohort.heatingCarbonModifiers
        #expect(abs(mixed.heatingCarbonModifier - (carbon[.naturalGas]! + carbon[.heatPump]!) / 2) < 1e-12)
        #expect(try model(UserProfile(heatingSources: [])).heatingCarbonModifier == carbon[.none])
        let gas = LifestyleEstimate(profile: UserProfile(heatingSources: [.naturalGas])).kgPerYear[.homeEnergy] ?? 0
        let both = LifestyleEstimate(profile: UserProfile(heatingSources: [.naturalGas, .electricResistance])).kgPerYear[.homeEnergy] ?? 0
        let electric = LifestyleEstimate(profile: UserProfile(heatingSources: [.electricResistance])).kgPerYear[.homeEnergy] ?? 0
        #expect(abs(both - (gas + electric) / 2) < 1e-6)
        // The cohort estimate counts the same mix.
        for profile in [UserProfile(heatingSources: [.naturalGas, .electricResistance]), UserProfile(heatingSources: [])] {
            let estimate = try #require(try model(profile).estimate(for: .carbon))
            #expect(abs(estimate - LifestyleEstimate(profile: profile).totalKg) < 1e-6)
        }
    }

    /// Home-energy carbon follows the heating source on the US-average grid: a heat pump beats gas, gas beats
    /// electric resistance, and an unheated home is lowest. Electricity still runs the other way.
    @Test func heatingCarbonFollowsTheSource() throws {
        let homeEnergy = { (sources: Set<HeatingSource>) in
            LifestyleEstimate(profile: UserProfile(heatingSources: sources)).kgPerYear[.homeEnergy] ?? 0
        }
        let none = homeEnergy([]), heatPump = homeEnergy([.heatPump]), gas = homeEnergy([.naturalGas])
        let district = homeEnergy([.districtHeating]), oil = homeEnergy([.oil])
        let resistance = homeEnergy([.electricResistance])
        #expect(none < heatPump && heatPump < gas && gas < resistance, "\([none, heatPump, gas, resistance])")
        #expect(gas < oil && abs(district - gas) / gas < 0.05)
        for source in HeatingSource.allCases where source != .none {
            #expect(homeEnergy([source]) > none, "\(source) emits more than no heating")
        }
        // The leaderboard estimate uses the same carbon.
        let pump = try model(UserProfile(heatingSources: [.heatPump]))
        let furnace = try model(UserProfile(heatingSources: [.naturalGas]))
        #expect(try #require(pump.estimate(for: .carbon)) < furnace.estimate(for: .carbon)!)
        // Electrically heated homes still draw more electricity.
        #expect(try #require(pump.estimate(for: .yearlyElectricity)) > furnace.estimate(for: .yearlyElectricity)!)
    }
}
