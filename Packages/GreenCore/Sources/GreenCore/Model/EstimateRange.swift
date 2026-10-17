/// A bare model estimate in the metric's canonical unit; the T4 fallback field from identify (spec §5.4).
public struct EstimateRange: Codable, Sendable, Hashable {
    public var value: Double
    public var low: Double
    public var high: Double

    public init(value: Double, low: Double, high: Double) {
        self.value = value
        self.low = low
        self.high = high
    }
}
