import Foundation

/// A seeded "friend" sampled from the cohort distribution. Always labeled as a simulated network (spec §9).
public struct SimulatedFriend: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    /// SF Symbol for the avatar.
    public var avatarSymbol: String
    /// Yearly sub-footprint per metric for the same categories as the user.
    public var yearly: [MetricKey: Double]

    public var initials: String {
        name.split(separator: " ").compactMap(\.first).map(String.init).joined()
    }
}

/// One row of the leaderboard (the user or a friend), sorted greenest first.
public struct LeaderboardEntry: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isUser: Bool
    public var value: Double
    public var greenerThan: Double
}

extension CohortModel {
    public static let friendNames = ["Maya Chen", "Jordan Okafor", "Priya Natarajan", "Leo Martins",
                                     "Sofia Rossi", "Sam Whitfield", "Aiko Tanaka", "Noah Becker"]
    public static let friendSymbols = ["leaf.fill", "bicycle", "sun.max.fill", "tree.fill",
                                       "drop.fill", "wind", "mountain.2.fill", "tram.fill"]
    /// Fixed base seed so the network is stable across launches.
    public static let networkSeed: UInt64 = 0x4C69_7665_4772_6565 // "LiveGree"

    /// Eight deterministic friends. Each has one lifestyle factor shared across metrics (correlation 0.8),
    /// so a low-carbon friend tends to be low on water and land too.
    public func simulatedFriends(categories: Set<Category>, count: Int = 8) -> [SimulatedFriend] {
        var generator = Xoshiro256StarStar(seed: Self.networkSeed ^ StableHash.fnv1a(baseline.region))
        return (0..<count).map { index in
            let lifestyle = generator.nextStandardNormal()
            var yearly: [MetricKey: Double] = [:]
            for metric in Self.comparedMetrics {
                let noise = generator.nextStandardNormal()
                guard let distribution = distribution(for: metric, categories: categories) else { continue }
                let z = 0.8 * lifestyle + 0.6 * noise
                yearly[metric] = exp(distribution.mu + distribution.sigma * z)
            }
            return SimulatedFriend(id: index, name: Self.friendNames[index % Self.friendNames.count],
                                   avatarSymbol: Self.friendSymbols[index % Self.friendSymbols.count], yearly: yearly)
        }
    }

    /// The user plus friends for one metric, greenest (smallest footprint) first.
    public func leaderboard(for footprint: ScannedFootprint, metric: MetricKey = .carbon,
                            userName: String = "You") -> [LeaderboardEntry] {
        let categories = footprint.categories(for: metric)
        guard let distribution = distribution(for: metric, categories: categories) else { return [] }
        var entries = simulatedFriends(categories: categories).compactMap { friend -> LeaderboardEntry? in
            guard let value = friend.yearly[metric] else { return nil }
            return LeaderboardEntry(id: "friend-\(friend.id)", name: friend.name, isUser: false, value: value,
                                    greenerThan: Percentiles.greenerThan(value, in: distribution))
        }
        if let value = footprint.yearly[metric] {
            entries.append(LeaderboardEntry(id: "user", name: userName, isUser: true, value: value,
                                            greenerThan: Percentiles.greenerThan(value, in: distribution)))
        }
        return entries.sorted { ($0.value, $0.id) < ($1.value, $1.id) }
    }
}
