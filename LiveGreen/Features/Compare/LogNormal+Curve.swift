import Foundation
import GreenCore

/// Plotting helpers for the cohort curve.
nonisolated extension LogNormal {
    struct CurvePoint: Hashable, Sendable {
        let x: Double
        let density: Double
    }

    func pdf(_ x: Double) -> Double {
        guard x > 0, sigma > 0 else { return 0 }
        let z = (log(x) - mu) / sigma
        return exp(-0.5 * z * z) / (x * sigma * (2 * Double.pi).squareRoot())
    }

    /// The value `z` standard deviations from the median in log space.
    func value(atZ z: Double) -> Double { exp(mu + sigma * z) }

    /// Log-spaced sample points covering ±`spread` σ.
    func curve(points: Int = 80, spread: Double = 3) -> [CurvePoint] {
        (0..<points).map { index in
            let z = -spread + 2 * spread * Double(index) / Double(points - 1)
            let x = value(atZ: z)
            return CurvePoint(x: x, density: pdf(x))
        }
    }
}
