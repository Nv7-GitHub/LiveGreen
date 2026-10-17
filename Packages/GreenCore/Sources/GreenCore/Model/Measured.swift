/// A number with an uncertainty range, unit, evidence tier and sources.
/// Every number shown in the app is one of these (spec §4).
public struct Measured: Codable, Sendable, Hashable {
    public let value: Double
    public let low: Double
    public let high: Double
    public let unit: MetricUnit
    public let tier: Tier
    public let sources: [Source]

    /// Creates a value; `low`/`high` are reordered and widened so `low <= value <= high`.
    public init(value: Double, low: Double, high: Double, unit: MetricUnit, tier: Tier, sources: [Source] = []) {
        let lo = min(low, high), hi = max(low, high)
        self.value = value
        self.low = min(lo, value)
        self.high = max(hi, value)
        self.unit = unit
        self.tier = tier
        self.sources = sources
    }

    /// A value with a symmetric relative range, e.g. `fraction: 0.5` gives ±50%.
    public init(value: Double, relativeRange fraction: Double, unit: MetricUnit, tier: Tier, sources: [Source] = []) {
        let delta = abs(value) * fraction
        self.init(value: value, low: value - delta, high: value + delta, unit: unit, tier: tier, sources: sources)
    }

    /// A value known exactly (zero-width range).
    public static func exact(_ value: Double, unit: MetricUnit, tier: Tier, sources: [Source] = []) -> Measured {
        Measured(value: value, low: value, high: value, unit: unit, tier: tier, sources: sources)
    }

    /// high/low ratio used by the question gate (spec §5.5). Infinite when low <= 0 and high > 0.
    public var spreadRatio: Double {
        if high == low { return 1 }
        guard low > 0 else { return .infinity }
        return high / low
    }

    /// Range width relative to the value.
    public var relativeUncertainty: Double {
        value == 0 ? 0 : (high - low) / (2 * abs(value))
    }

    /// Returns a copy with value and range multiplied by `factor` (e.g. per-unit → yearly).
    public func scaled(by factor: Double) -> Measured {
        Measured(value: value * factor, low: low * factor, high: high * factor, unit: unit, tier: tier, sources: sources)
    }
}
