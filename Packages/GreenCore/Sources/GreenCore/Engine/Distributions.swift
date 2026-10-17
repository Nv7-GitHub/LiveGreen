import Foundation

/// Standard normal helpers.
public enum Normal {
    /// z for the 95th percentile, so [z05, z95] is a 90% interval.
    public static let z95 = 1.6448536269514722

    /// Φ(z) via the error function.
    public static func cdf(_ z: Double) -> Double {
        0.5 * (1 + erf(z / 2.0.squareRoot()))
    }

    /// Φ⁻¹(p), Acklam's rational approximation refined with one Halley step (|error| < 1e-12).
    public static func quantile(_ p: Double) -> Double {
        guard p > 0 else { return -.infinity }
        guard p < 1 else { return .infinity }
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
        let low = 0.02425
        var x: Double
        if p < low {
            let q = (-2 * log(p)).squareRoot()
            x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if p <= 1 - low {
            let q = p - 0.5, r = q * q
            x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
                (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        } else {
            let q = (-2 * log(1 - p)).squareRoot()
            x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
                ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let e = cdf(x) - p
        let u = e * (2 * Double.pi).squareRoot() * exp(x * x / 2)
        x -= u / (1 + x * u / 2)
        return x
    }
}

/// Lognormal distribution: ln X ~ N(mu, sigma²).
public struct LogNormal: Sendable, Hashable {
    public let mu: Double
    public let sigma: Double

    public init(mu: Double, sigma: Double) {
        self.mu = mu
        self.sigma = max(sigma, 0)
    }

    public init(median: Double, sigma: Double) {
        self.init(mu: log(median), sigma: sigma)
    }

    /// Fits `low`/`high` as the 5th/95th percentiles. Requires 0 < low <= high.
    public init?(p05 low: Double, p95 high: Double) {
        guard low > 0, high >= low else { return nil }
        self.init(mu: (log(low) + log(high)) / 2, sigma: (log(high) - log(low)) / (2 * Normal.z95))
    }

    public var median: Double { exp(mu) }
    public var mean: Double { exp(mu + sigma * sigma / 2) }

    public func cdf(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard sigma > 0 else { return x >= median ? 1 : 0 }
        return Normal.cdf((log(x) - mu) / sigma)
    }

    public func quantile(_ p: Double) -> Double { exp(mu + sigma * Normal.quantile(p)) }

    public func sample<G: RandomNumberGenerator>(using generator: inout G) -> Double {
        exp(mu + sigma * generator.nextStandardNormal())
    }
}

/// How a `Measured` is sampled in Monte Carlo propagation (spec §5.6).
public enum UncertainValue: Sendable, Hashable {
    case constant(Double)
    /// Positive ranges: lognormal with low/high as the 90% interval.
    case logNormal(LogNormal)
    /// Ranges touching zero or negative: normal with low/high as the 90% interval.
    case normal(mean: Double, sd: Double)

    public init(_ measured: Measured) {
        if measured.high <= measured.low {
            self = .constant(measured.value)
        } else if let fitted = LogNormal(p05: measured.low, p95: measured.high) {
            self = .logNormal(fitted)
        } else {
            self = .normal(mean: (measured.low + measured.high) / 2, sd: (measured.high - measured.low) / (2 * Normal.z95))
        }
    }

    public func sample<G: RandomNumberGenerator>(using generator: inout G) -> Double {
        switch self {
        case .constant(let value): value
        case .logNormal(let distribution): distribution.sample(using: &generator)
        case .normal(let mean, let sd): mean + sd * generator.nextStandardNormal()
        }
    }
}
