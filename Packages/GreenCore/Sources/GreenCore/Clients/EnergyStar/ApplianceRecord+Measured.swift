import Foundation

extension ApplianceRecord {
    /// Certified test-procedure figures; ±5% covers unit-to-unit and setting variation.
    static let relativeRange = 0.05

    public var recordSource: Source {
        Source(title: "\(datasetName): \(brand) \(model)", url: sourceURL, tier: .exactRecord)
    }

    /// T1 power metrics present in the record.
    public var measuredMetrics: [MetricKey: Measured] {
        let figures: [(MetricKey, Double?)] = [
            (.powerOn, onModeWatts), (.standbyPower, standbyWatts), (.yearlyElectricity, annualKWh),
        ]
        var metrics: [MetricKey: Measured] = [:]
        for case let (metric, value?) in figures where value.isFinite && value >= 0 {
            metrics[metric] = Measured(value: value, relativeRange: Self.relativeRange, unit: metric.unit,
                                       tier: .exactRecord, sources: [recordSource])
        }
        return metrics
    }
}
