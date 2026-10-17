import Foundation

/// SplitMix64: tiny seed expander (Steele, Lea & Flood 2014). Used to seed `Xoshiro256StarStar`.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// xoshiro256** (Blackman & Vigna 2018): fast, deterministic across platforms and Swift versions.
public struct Xoshiro256StarStar: RandomNumberGenerator, Sendable {
    private var s: (UInt64, UInt64, UInt64, UInt64)

    public init(seed: UInt64) {
        var mixer = SplitMix64(seed: seed)
        s = (mixer.next(), mixer.next(), mixer.next(), mixer.next())
    }

    public mutating func next() -> UInt64 {
        let result = rotl(s.1 &* 5, 7) &* 9
        let t = s.1 << 17
        s.2 ^= s.0
        s.3 ^= s.1
        s.1 ^= s.2
        s.0 ^= s.3
        s.2 ^= t
        s.3 = rotl(s.3, 45)
        return result
    }

    private func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }
}

extension RandomNumberGenerator {
    /// Uniform double in [0, 1) from the top 53 bits. Independent of the standard library's float conversion.
    public mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    /// Standard normal draw via Box–Muller (one value per call; the pair's second value is discarded for simplicity).
    public mutating func nextStandardNormal() -> Double {
        let u1 = 1 - nextUnitInterval() // (0, 1]
        let u2 = nextUnitInterval()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// Stable 64-bit FNV-1a hash for deriving seeds from strings (Swift's `hashValue` is randomized per process).
public enum StableHash {
    public static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// Seed derived from a UUID (same folding as `ScanResult.seed`).
    public static func seed(_ id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { raw in
            raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self) ^ raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
        }
    }
}
