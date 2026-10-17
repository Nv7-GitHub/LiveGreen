import Foundation
import Testing
@testable import GreenCore

@Suite("Seeded randomness and distributions")
struct DistributionTests {
    @Test func xoshiroIsDeterministicAndSeedSensitive() {
        var a = Xoshiro256StarStar(seed: 42), b = Xoshiro256StarStar(seed: 42), c = Xoshiro256StarStar(seed: 43)
        let first = (0..<5).map { _ in a.next() }
        #expect(first == (0..<5).map { _ in b.next() })
        #expect(first != (0..<5).map { _ in c.next() })
    }

    @Test func splitMixMatchesReferenceVector() {
        // Reference output of SplitMix64 seeded with 0 (Vigna's splitmix64.c).
        var generator = SplitMix64(seed: 0)
        #expect(generator.next() == 0xE220_A839_7B1D_CDAF)
        #expect(generator.next() == 0x6E78_9E6A_A1B9_65F4)
    }

    @Test func unitIntervalAndNormalMoments() {
        var generator = Xoshiro256StarStar(seed: 7)
        let uniforms = (0..<20_000).map { _ in generator.nextUnitInterval() }
        #expect(uniforms.allSatisfy { $0 >= 0 && $0 < 1 })
        #expect(abs(uniforms.reduce(0, +) / 20_000 - 0.5) < 0.01)
        let normals = (0..<20_000).map { _ in generator.nextStandardNormal() }
        let mean = normals.reduce(0, +) / 20_000
        let variance = normals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 20_000
        #expect(abs(mean) < 0.03)
        #expect(abs(variance - 1) < 0.04)
    }

    @Test func normalCDFAndQuantileMatchTables() {
        #expect(abs(Normal.cdf(0) - 0.5) < 1e-12)
        #expect(abs(Normal.cdf(1) - 0.841_344_746_068_543) < 1e-9)
        #expect(abs(Normal.cdf(-2) - 0.022_750_131_948_179) < 1e-9)
        #expect(abs(Normal.cdf(Normal.z95) - 0.95) < 1e-9)
        for p in [0.001, 0.01, 0.05, 0.3, 0.5, 0.8, 0.95, 0.999] {
            #expect(abs(Normal.cdf(Normal.quantile(p)) - p) < 1e-10)
        }
    }

    @Test func lognormalCDFAgainstHandValues() throws {
        let distribution = LogNormal(median: 1000, sigma: 0.6)
        #expect(abs(distribution.cdf(1000) - 0.5) < 1e-12)
        // x = median·e^σ ⇒ z = 1 ⇒ Φ(1).
        #expect(abs(distribution.cdf(1000 * exp(0.6)) - 0.841_344_746) < 1e-8)
        // x = median·e^(−2σ) ⇒ Φ(−2).
        #expect(abs(distribution.cdf(1000 * exp(-1.2)) - 0.022_750_132) < 1e-8)
        #expect(distribution.cdf(0) == 0)
        #expect(abs(distribution.mean - 1000 * exp(0.18)) < 1e-9)
        let fitted = try #require(LogNormal(p05: 50, p95: 200))
        #expect(abs(fitted.quantile(0.05) - 50) < 1e-6)
        #expect(abs(fitted.quantile(0.95) - 200) < 1e-6)
        #expect(LogNormal(p05: 0, p95: 10) == nil)
    }

    @Test func uncertainValueChoosesDistribution() {
        #expect(UncertainValue(.exact(3, unit: .watts, tier: .exactRecord)) == .constant(3))
        if case .logNormal = UncertainValue(Measured(value: 10, low: 5, high: 20, unit: .watts, tier: .estimate)) {} else {
            Issue.record("positive range should be lognormal")
        }
        if case .normal = UncertainValue(Measured(value: 1, low: 0, high: 2, unit: .watts, tier: .estimate)) {} else {
            Issue.record("range touching zero should be normal")
        }
    }
}

@Suite("Monte Carlo propagation")
struct MonteCarloTests {
    let a = Measured(value: 100, low: 70, high: 140, unit: .kgCO2e, tier: .exactRecord, sources: [Source(title: "A", tier: .exactRecord)])
    let b = Measured(value: 50, low: 20, high: 120, unit: .kgCO2e, tier: .estimate, sources: [Source(title: "B", tier: .estimate)])

    @Test func sameSeedSameOutput() throws {
        let first = try #require(MonteCarlo(seed: 99).sum([a, b]))
        let second = try #require(MonteCarlo(seed: 99).sum([a, b]))
        #expect(first == second)
        let other = try #require(MonteCarlo(seed: 100).sum([a, b]))
        #expect(other.low != first.low)
        #expect(MonteCarlo.defaultSampleCount == 2000)
    }

    @Test func sumKeepsPointValueAndNarrowsRelativeSpread() throws {
        let total = try #require(MonteCarlo(seed: 1).sum([a, b]))
        #expect(total.value == 150)
        #expect(total.low < 150 && total.high > 150)
        // Independent errors partly cancel: the 90% band is narrower than adding the bounds.
        #expect(total.low > a.low + b.low)
        #expect(total.high < a.high + b.high)
        #expect(total.tier == .estimate)
        #expect(total.sources.map(\.title) == ["A", "B"])
    }

    @Test func productMatchesLognormalAlgebra() throws {
        // Product of lognormals is lognormal: σ² adds, so the 90% band is exp(±z·√(σa²+σb²)) around the medians' product.
        let x = Measured(value: 10, low: 5, high: 20, unit: .watts, tier: .factorModel)
        let y = Measured(value: 4, low: 2, high: 8, unit: .watts, tier: .factorModel)
        let product = try #require(MonteCarlo(seed: 5).product([x, y], unit: .kilowattHoursPerYear))
        let sigma = log(2) / Normal.z95 * 2.0.squareRoot()
        #expect(product.value == 40)
        #expect(abs(product.low / (40 * exp(-Normal.z95 * sigma)) - 1) < 0.08)
        #expect(abs(product.high / (40 * exp(Normal.z95 * sigma)) - 1) < 0.08)
    }

    @Test func constantsPropagateExactly() throws {
        let exact = MonteCarlo(seed: 3).sum([.exact(2, unit: .grams, tier: .exactRecord), .exact(3, unit: .grams, tier: .factorModel)])
        let total = try #require(exact)
        #expect(total.value == 5 && total.low == 5 && total.high == 5)
        #expect(MonteCarlo(seed: 3).sum([]) == nil)
    }

    @Test func percentileInterpolates() {
        #expect(MonteCarlo.percentile([1, 2, 3, 4, 5], 0.5) == 3)
        #expect(MonteCarlo.percentile([0, 10], 0.25) == 2.5)
        #expect(MonteCarlo.percentile([7], 0.95) == 7)
    }
}
