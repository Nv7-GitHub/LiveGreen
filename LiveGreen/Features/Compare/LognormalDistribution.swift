import Foundation

/// A lognormal distribution parameterized by its median and log-space σ.
nonisolated struct LognormalDistribution: Hashable, Sendable {
    let median: Double
    let sigma: Double

    private var mu: Double { log(median) }

    /// P(X ≤ x).
    func cdf(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard sigma > 0 else { return x < median ? 0 : 1 }
        return 0.5 * erfc(-(log(x) - mu) / (sigma * 2.0.squareRoot()))
    }

    func pdf(_ x: Double) -> Double {
        guard x > 0, sigma > 0 else { return 0 }
        let z = (log(x) - mu) / sigma
        return exp(-0.5 * z * z) / (x * sigma * (2 * Double.pi).squareRoot())
    }

    /// The value `z` standard deviations from the median in log space.
    func value(atZ z: Double) -> Double { median * exp(sigma * z) }

    /// Log-spaced sample points covering ±`spread` σ, for plotting.
    func curve(points: Int = 80, spread: Double = 3) -> [CurvePoint] {
        (0..<points).map { index in
            let z = -spread + 2 * spread * Double(index) / Double(points - 1)
            let x = value(atZ: z)
            return CurvePoint(x: x, density: pdf(x))
        }
    }

    struct CurvePoint: Hashable, Sendable {
        let x: Double
        let density: Double
    }
}
