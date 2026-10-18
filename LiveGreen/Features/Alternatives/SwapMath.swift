import Foundation
import GreenCore

/// Display helpers for the swap charts; the comparison math itself is `GreenCore.SwapMath`.
extension SwapMath {
    /// Axis ticks at round numbers in the unit shown (0/50/100/150 lb rather than 55.1/110/165 lb, which are
    /// round kilograms converted), returned in canonical units for plotting. The last tick is at or above `maxValue`,
    /// so it also bounds the axis.
    static func axisTicks(upTo maxValue: Double, unit: MetricUnit, count: Int = 3) -> [Double] {
        let factor = DisplayUnits.factor(for: unit)
        let top = maxValue * factor
        guard top > 0, top.isFinite, factor > 0 else { return [0, 1 / max(factor, 1)] }
        let step = niceStep(top / Double(max(count, 1)))
        let steps = Int((top / step - 1e-9).rounded(.up))
        return (0...max(steps, 1)).map { Double($0) * step / factor }
    }

    /// 1, 2, 2.5 or 5 times a power of ten, at least `raw`.
    nonisolated static func niceStep(_ raw: Double) -> Double {
        let magnitude = pow(10, floor(log10(raw)))
        let fraction = raw / magnitude
        let nice: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10
        return nice * magnitude
    }
}
