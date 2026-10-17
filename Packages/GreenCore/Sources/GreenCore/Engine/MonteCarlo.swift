/// Fixed-seed Monte Carlo propagation of `Measured` values (spec §5.6).
/// Each input is sampled as `UncertainValue`; the result's value is `f` of the point values and its
/// range is the 5th–95th percentile of `f` over the samples. The same seed and salt always give the same output.
public struct MonteCarlo: Sendable {
    public static let defaultSampleCount = 2000

    public let seed: UInt64
    public let sampleCount: Int

    public init(seed: UInt64, sampleCount: Int = MonteCarlo.defaultSampleCount) {
        self.seed = seed
        self.sampleCount = max(sampleCount, 1)
    }

    /// Propagates `f` over independent inputs. `salt` decorrelates different calculations sharing one seed.
    public func propagate(_ inputs: [Measured], unit: MetricUnit, salt: String,
                          _ f: ([Double]) -> Double) -> Measured {
        let tier = inputs.map(\.tier).max() ?? .estimate
        let sources = Self.mergedSources(inputs)
        let value = f(inputs.map(\.value))
        let distributions = inputs.map(UncertainValue.init)
        if distributions.allSatisfy({ if case .constant = $0 { true } else { false } }) {
            return Measured.exact(value, unit: unit, tier: tier, sources: sources)
        }
        var generator = Xoshiro256StarStar(seed: seed ^ StableHash.fnv1a(salt))
        var draws = [Double](repeating: 0, count: inputs.count)
        var outputs: [Double] = []
        outputs.reserveCapacity(sampleCount)
        for _ in 0..<sampleCount {
            for index in distributions.indices {
                draws[index] = distributions[index].sample(using: &generator)
            }
            let output = f(draws)
            if output.isFinite { outputs.append(output) }
        }
        outputs.sort()
        guard !outputs.isEmpty else { return Measured.exact(value, unit: unit, tier: tier, sources: sources) }
        return Measured(value: value, low: Self.percentile(outputs, 0.05), high: Self.percentile(outputs, 0.95),
                        unit: unit, tier: tier, sources: sources)
    }

    /// Sum of values sharing a unit; nil for an empty list.
    public func sum(_ inputs: [Measured], salt: String = "sum") -> Measured? {
        guard let unit = inputs.first?.unit else { return nil }
        return propagate(inputs, unit: unit, salt: salt) { $0.reduce(0, +) }
    }

    /// Product of values, reported in `unit`; nil for an empty list.
    public func product(_ inputs: [Measured], unit: MetricUnit, salt: String = "product") -> Measured? {
        guard !inputs.isEmpty else { return nil }
        return propagate(inputs, unit: unit, salt: salt) { $0.reduce(1, *) }
    }

    /// numerator ÷ denominator, reported in `unit`.
    public func quotient(_ numerator: Measured, _ denominator: Measured, unit: MetricUnit,
                         salt: String = "quotient") -> Measured {
        propagate([numerator, denominator], unit: unit, salt: salt) { $0[1] == 0 ? .nan : $0[0] / $0[1] }
    }

    /// Linear-interpolated percentile of ascending-sorted values, p in [0, 1].
    public static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard let first = sorted.first else { return .nan }
        guard sorted.count > 1 else { return first }
        let position = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Union of sources, keeping first-seen order.
    static func mergedSources(_ inputs: [Measured]) -> [Source] {
        var seen = Set<Source>()
        return inputs.flatMap(\.sources).filter { seen.insert($0).inserted }
    }
}
