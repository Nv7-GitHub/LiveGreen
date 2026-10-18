import Foundation

/// A seeded "friend" sampled from the region's distribution (spec §9).
public struct SimulatedFriend: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    /// SF Symbol for the avatar.
    public var avatarSymbol: String
    /// Whole yearly footprint per leaderboard metric, canonical units.
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
    public static let friendNames = ["Saahil Shah", "Yuti Purohit", "Nishant Vikramaditya", "Vishnu Mangipudi",
                                     "Sebastian Bagley", "Daniel Hoang", "Albert Wu", "Shuji Hokosawa", "Louis Liu"]
    public static let friendSymbols = ["leaf.fill", "bicycle", "sun.max.fill", "tree.fill",
                                       "drop.fill", "wind", "mountain.2.fill", "tram.fill", "flame.fill"]
    /// Fixed base seed so the network is stable across launches.
    public static let networkSeed: UInt64 = 0x4C69_7665_4772_6565 // "LiveGree"

    /// Nine deterministic friends drawn from the region's people (`regionalDistribution`), not from people like
    /// you, so your profile decides where you land. Draws are stratified: each friend gets their own slice of
    /// the distribution (jittered within it), so the nine span it like a real circle of people instead of
    /// bunching by chance. A shared lifestyle factor orders the slices across metrics (correlation ≈ 0.8),
    /// so a low-carbon friend tends to use less water, land and electricity too.
    public func simulatedFriends(count: Int = friendNames.count) -> [SimulatedFriend] {
        var generator = Xoshiro256StarStar(seed: Self.networkSeed ^ StableHash.fnv1a(baseline.region))
        // Names are dealt in a shuffled order, so who lands where on the board is random but stable.
        var names = Self.friendNames
        for index in names.indices.reversed() where index > 0 {
            names.swapAt(index, Int(generator.next() % UInt64(index + 1)))
        }
        let lifestyle = (0..<count).map { _ in generator.nextStandardNormal() }
        var yearly = Array(repeating: [MetricKey: Double](), count: count)
        for metric in Self.leaderboardMetrics {
            guard let distribution = regionalDistribution(for: metric) else { continue }
            let slices = (0..<count).map { slice in
                Normal.quantile((Double(slice) + 0.25 + 0.5 * generator.nextUnitInterval()) / Double(count))
            }
            let order = (0..<count).map { (0.8 * lifestyle[$0] + 0.6 * generator.nextStandardNormal(), $0) }
                .sorted { $0 < $1 }
            for (slice, friend) in order.enumerated() {
                yearly[friend.1][metric] = exp(distribution.mu + distribution.sigma * slices[slice])
            }
        }
        return (0..<count).map { index in
            SimulatedFriend(id: index, name: names[index % names.count],
                            avatarSymbol: Self.friendSymbols[index % Self.friendSymbols.count], yearly: yearly[index])
        }
    }

    /// The user plus friends for one metric, greenest (smallest footprint) first. Everyone is a whole yearly
    /// footprint: friends from the region's distribution, you from `estimate` (profile plus scans).
    public func leaderboard(for footprint: ScannedFootprint, metric: MetricKey = .carbon,
                            userName: String = "You") -> [LeaderboardEntry] {
        guard let distribution = regionalDistribution(for: metric),
              let value = estimate(for: metric, scanned: footprint) else { return [] }
        var entries = simulatedFriends().compactMap { friend -> LeaderboardEntry? in
            guard let value = friend.yearly[metric] else { return nil }
            return LeaderboardEntry(id: "friend-\(friend.id)", name: friend.name, isUser: false, value: value,
                                    greenerThan: Percentiles.greenerThan(value, in: distribution))
        }
        entries.append(LeaderboardEntry(id: "user", name: userName, isUser: true, value: value,
                                        greenerThan: Percentiles.greenerThan(value, in: distribution)))
        return entries.sorted { ($0.value, $0.id) < ($1.value, $1.id) }
    }
}
