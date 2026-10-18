import Foundation
import Testing
@testable import GreenCore

@Suite("Everyday equivalences")
struct EquivalencesTests {
    @Test func countsReadAsPeopleSayThem() {
        #expect(Equivalences.format(1) == "1")
        #expect(Equivalences.format(2.46) == "2.5")
        #expect(Equivalences.format(3.0) == "3")
        #expect(Equivalences.format(42.4) == "42")
        #expect(Equivalences.format(1_243) == "1,200")
        #expect(Equivalences.format(34_567) == "35,000")
        #expect(Equivalences.format(996_000) == "1 million")
        #expect(Equivalences.format(3_420_000) == "3.4 million")
    }

    @Test func carMilesFollowTheEPAFactor() throws {
        let miles = try #require(Equivalences.candidates(for: .carbon, amount: 393, imperial: true).first { $0.id == "car" })
        #expect(miles.phrase == "driving 1,000 miles in an average gas car")
        let km = try #require(Equivalences.candidates(for: .carbon, amount: 393, imperial: false).first { $0.id == "car" })
        #expect(km.phrase == "driving 1,600 km in an average gas car")
    }

    @Test func oneThingIsSingular() throws {
        let shower = try #require(Equivalences.candidates(for: .water, amount: 15.8 * 3.785_41, imperial: true)
            .first { $0.id == "showers" })
        #expect(shower.phrase == "taking one average shower")
        let glasses = try #require(Equivalences.candidates(for: .water, amount: 1, imperial: false).first { $0.id == "glasses" })
        #expect(glasses.phrase == "drinking 4 glasses of water")
    }

    @Test func onlyReadableCountsAreOffered() {
        // 2 kg CO₂e is a few miles or a hundred-odd phone charges, never 0.03 tree seedlings or a home's year.
        let small = Set(Equivalences.candidates(for: .carbon, amount: 2, imperial: true).map(\.id))
        #expect(small.contains("car") && small.contains("phoneCarbon"))
        #expect(!small.contains("seedlings") && !small.contains("homeYears"))
        for metric in MetricKey.allCases {
            for amount in [0.5, 12.0, 800.0, 15_000.0, 2_000_000.0] {
                for option in Equivalences.candidates(for: metric, amount: amount, imperial: true) {
                    #expect(option.count >= 1, "\(option.id) at \(amount)")
                    #expect(!option.phrase.contains("{n}"))
                    #expect(!option.source.isEmpty)
                }
            }
        }
        #expect(Equivalences.candidates(for: .carbon, amount: 0, imperial: true).isEmpty)
        #expect(Equivalences.candidates(for: .carbon, amount: .nan, imperial: true).isEmpty)
        #expect(Equivalences.candidates(for: .waterPollution, amount: 40, imperial: true).isEmpty)
    }

    @Test func picksVaryBySeedButHoldForOne() {
        let picks = (0..<40).compactMap { seed in
            Equivalences.pick(for: .carbon, amount: 1_500, imperial: true, seed: UInt64(seed))
        }
        #expect(picks.count == 40)
        #expect(Set(picks.map(\.id)).count >= 4, "several comparisons in rotation")
        #expect(Set(picks.map { $0.sentence() }.map { $0.components(separatedBy: " ").prefix(2).joined() }).count > 1,
                "the opening varies too")
        let seed = Equivalences.seed("scan-1|carbon", on: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(Equivalences.pick(for: .carbon, amount: 1_500, imperial: true, seed: seed)
            == Equivalences.pick(for: .carbon, amount: 1_500, imperial: true, seed: seed))
        let nextDay = Equivalences.seed("scan-1|carbon", on: Date(timeIntervalSince1970: 1_800_000_000 + 86_400))
        #expect(seed != nextDay)
    }

    @Test func pickAvoidsComparisonsAlreadyShown() throws {
        let all = Set(Equivalences.candidates(for: .carbon, amount: 1_500, imperial: true).map(\.id))
        let shown = all.subtracting(["seedlings"])
        for seed in 0..<10 {
            let pick = try #require(Equivalences.pick(for: .carbon, amount: 1_500, imperial: true, seed: UInt64(seed),
                                                      avoiding: shown))
            #expect(pick.id == "seedlings")
        }
        // With nothing new left it still answers.
        #expect(Equivalences.pick(for: .carbon, amount: 1_500, imperial: true, seed: 1, avoiding: all) != nil)
    }

    @Test func sentencesOpenForAnAmountOrASaving() throws {
        let pick = try #require(Equivalences.pick(for: .plasticMass, amount: 127, imperial: true, seed: 7))
        #expect(pick.phrase == "10 single-use plastic water bottles")
        #expect(pick.sentence().hasSuffix(" 10 single-use plastic water bottles!"))
        #expect(Equivalences.openings(.amount).contains { pick.sentence().hasPrefix($0) })
        #expect(Equivalences.openings(.saving).contains { pick.sentence(.saving).hasPrefix($0) })
        var first = pick
        first.opening = 0
        #expect(first.sentence() == "That's like 10 single-use plastic water bottles!")
        #expect(first.sentence(.saving) == "That saves as much as 10 single-use plastic water bottles!")
    }
}
