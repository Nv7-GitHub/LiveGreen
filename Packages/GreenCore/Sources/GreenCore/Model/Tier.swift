/// Evidence tier of a number, from most to least trustworthy (spec §5.4).
public enum Tier: Int, Codable, Sendable, Hashable, CaseIterable, Comparable {
    /// Exact database record (Open Food Facts, ENERGY STAR, ASUS PCF).
    case exactRecord = 1
    /// Value researched from a cited spec sheet or web page.
    case researchedSpec
    /// Reference-table factor multiplied by identified quantities.
    case factorModel
    /// Bounded model estimate with a deliberately wide range.
    case estimate

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Short badge text, e.g. "T1".
    public var badge: String { "T\(rawValue)" }

    public var displayName: String {
        switch self {
        case .exactRecord: "Exact record"
        case .researchedSpec: "Researched spec"
        case .factorModel: "Factor model"
        case .estimate: "Estimate"
        }
    }
}
