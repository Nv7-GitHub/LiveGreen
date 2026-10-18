import Foundation
import Testing
@testable import GreenCore

@Suite("Overall GreenScore and the overall board")
struct OverallGreenScoreTests {
    static let typical = UserProfile(householdSize: 2, commuteKmPerWeekByMode: [.car: 150], homeType: .detachedHouse)
    static let green = UserProfile(householdSize: 3, meatMealsPerWeek: 0, dairyMealsPerWeek: 0, commuteKmPerWeekByMode: [:],
                                   homeType: .apartment, newClothesPerYear: 34)
    static let heavy = UserProfile(householdSize: 1, commuteKmPerWeekByMode: [.car: 500], homeType: .detachedHouse,
                                   heatingSources: [.electricResistance], newClothesPerYear: 83)

    func model(_ profile: UserProfile = .default) throws -> CohortModel {
        try #require(CohortModel(profile: profile, store: .bundled))
    }

    @Test func theTypicalPersonScoresFifty() throws {
        let model = try model()
        let typical = model.greenScore(model.typicalYearly)
        #expect(abs(typical.score) < 1e-12)
        #expect(typical.points == 50)
        #expect(Set(typical.changes.keys) == Set(CohortModel.leaderboardMetrics))
    }

    @Test func everyMetricCountsEquallyAndIsClamped() throws {
        let model = try model()
        var yearly = model.typicalYearly
        // Half the typical carbon, everything else typical: ln 2 over four metrics.
        yearly[.carbon] = try #require(yearly[.carbon]) / 2
        let halfCarbon = model.greenScore(yearly)
        #expect(abs(halfCarbon.score - log(2) / 4) < 1e-3)
        #expect(abs(try #require(halfCarbon.ratio(for: .carbon)) - 0.5) < 1e-3)
        // A carbon cut cannot hide water four times the typical amount.
        yearly[.water] = try #require(yearly[.water]) * 4
        #expect(model.greenScore(yearly).score < 0)
        // 100× the typical footprint everywhere is clamped to 4×: zero points, not below.
        let huge = model.typicalYearly.mapValues { $0 * 100 }
        #expect(model.greenScore(huge).points == 0)
        #expect(model.greenScore(model.typicalYearly.mapValues { $0 / 100 }).points == 100)
    }

    @Test func boardRanksEveryoneGreenestFirst() throws {
        let board = try model().overallLeaderboard(for: .empty)
        #expect(board.count == CohortModel.friendNames.count + 1)
        #expect(board.filter(\.isUser).count == 1)
        #expect(zip(board, board.dropFirst()).allSatisfy { $0.greenScore.score >= $1.greenScore.score })
        // Friends' scores come from their yearly footprints on every metric.
        let model = try model()
        for friend in model.simulatedFriends() {
            let entry = try #require(board.first { $0.id == "friend-\(friend.id)" })
            #expect(entry.greenScore == model.greenScore(friend.yearly))
        }
    }

    @Test func greenerProfilesRankHigherOverall() throws {
        func rank(_ profile: UserProfile) throws -> Int {
            try #require(try model(profile).overallLeaderboard(for: .empty).firstIndex { $0.isUser }) + 1
        }
        #expect(try rank(Self.green) < rank(Self.typical))
        #expect(try rank(Self.typical) <= rank(Self.heavy))
        #expect(try rank(Self.green) <= 4)
    }

    @Test func smartPlugSchedulingLowersCarbonAndRaisesTheScore() throws {
        let model = try model(Self.typical)
        let plain = ScannedFootprint(byCategory: [.electronic: [.carbon: 200]])
        let scheduled = ScannedFootprint(byCategory: [.electronic: [.carbon: 200]], scheduledSavingsKg: 120)
        let before = try #require(model.estimate(for: .carbon, scanned: plain))
        let after = try #require(model.estimate(for: .carbon, scanned: scheduled))
        #expect(abs(before - after - 120) < 1e-9)
        // Shifting charging leaves the electricity the same.
        #expect(model.estimate(for: .yearlyElectricity, scanned: plain) == model.estimate(for: .yearlyElectricity, scanned: scheduled))
        let user = { (footprint: ScannedFootprint) in
            model.overallLeaderboard(for: footprint).first(where: \.isUser)!.greenScore.score
        }
        #expect(user(scheduled) > user(plain))
        // The carbon board counts it too, so the chips and the overall board agree.
        let carbon = { (footprint: ScannedFootprint) in model.leaderboard(for: footprint, metric: .carbon).first(where: \.isUser)!.value }
        #expect(abs(carbon(plain) - carbon(scheduled) - 120) < 1e-9)
    }

    @Test func scheduleKeepsItsBaselineForYearlySavings() {
        let window = GreenWindow(hours: [2, 3, 4], averageIntensity: 180)
        let schedule = window.schedule(timeZone: TimeZone(identifier: "UTC")!, baselineIntensity: 280)
        // 0.25 kWh a day × 365 × (280 − 180) g/kWh = 9.125 kg a year.
        #expect(abs((schedule.yearlySavingsKg(dailyKWh: 0.25) ?? 0) - 9.125) < 1e-9)
        #expect(PlugSchedule(onHours: [2], expectedIntensity: 180).yearlySavingsKg(dailyKWh: 1) == nil)
    }

    @Test func schedulesSavedBeforeTheBaselineStillDecode() throws {
        let json = #"{"onHours":[1,2],"timeZoneIdentifier":"UTC","createdAt":0,"expectedIntensity":150}"#
        let schedule = try JSONDecoder().decode(PlugSchedule.self, from: Data(json.utf8))
        #expect(schedule.baselineIntensity == nil && schedule.expectedIntensity == 150)
    }
}
