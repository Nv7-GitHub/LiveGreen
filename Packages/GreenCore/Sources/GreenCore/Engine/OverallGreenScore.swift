import Foundation

/// A person's GreenScore (spec §9): the swap rule (`GreenScore`) applied to a whole yearly footprint, with the
/// region's typical person (each leaderboard metric's median) as the original. Carbon, electricity, water and
/// land count equally, so a low carbon footprint cannot hide a large water one, and each metric's log ratio is
/// clamped to ±ln 4 as for swaps.
public struct PersonalGreenScore: Sendable, Hashable {
    /// Mean change across the metrics against the typical person; positive is greener.
    public var score: Double
    /// Change per metric (log ratio, positive = smaller footprint than typical), before clamping.
    public var changes: [MetricKey: Double]

    public init(score: Double, changes: [MetricKey: Double]) {
        self.score = score
        self.changes = changes
    }

    /// 0–100 points: 50 is the typical person, 100 a footprint 4× smaller on every metric, 0 one 4× larger.
    public var points: Int {
        let limit = log(GreenScore.clampRatio)
        return Int((50 + 50 * min(max(score, -limit), limit) / limit).rounded())
    }

    /// The footprint against the typical person's as a geometric mean ratio across metrics (0.8 = 20% smaller).
    public var footprintRatio: Double { exp(-score) }

    /// Footprint ratio for one metric against the typical person (0.8 = 20% smaller).
    public func ratio(for metric: MetricKey) -> Double? { changes[metric].map { exp(-$0) } }
}

/// One row of the overall board (the user or a friend), greenest first.
public struct OverallEntry: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isUser: Bool
    public var greenScore: PersonalGreenScore
}

extension CohortModel {
    /// The region's typical person: each leaderboard metric's median yearly footprint.
    public var typicalYearly: [MetricKey: Double] {
        Self.leaderboardMetrics.reduce(into: [:]) { typical, metric in
            typical[metric] = regionalDistribution(for: metric)?.median
        }
    }

    /// Your yearly footprint for every leaderboard metric (`estimate`, profile plus scans and plug schedules).
    public func userYearly(scanned: ScannedFootprint = .empty) -> [MetricKey: Double] {
        Self.leaderboardMetrics.reduce(into: [:]) { yearly, metric in
            yearly[metric] = estimate(for: metric, scanned: scanned)
        }
    }

    /// GreenScore of a yearly footprint against the region's typical person, over the metrics both have.
    public func greenScore(_ yearly: [MetricKey: Double]) -> PersonalGreenScore {
        let typical = typicalYearly
        var changes: [MetricKey: Double] = [:]
        for metric in Self.leaderboardMetrics {
            guard let median = typical[metric], let value = yearly[metric] else { continue }
            changes[metric] = GreenScore.change(metric, current: median, swap: value)
        }
        let limit = log(GreenScore.clampRatio)
        // In metric order, so the sum (and so the ranking) does not depend on dictionary order.
        let clamped = Self.leaderboardMetrics.compactMap { changes[$0] }.map { min(max($0, -limit), limit) }
        let score = clamped.isEmpty ? 0 : clamped.reduce(0, +) / Double(clamped.count)
        return PersonalGreenScore(score: score, changes: changes)
    }

    /// You and your friends ranked by GreenScore, greenest first: everyone's footprint on every leaderboard
    /// metric at once, where `leaderboard(for:metric:)` ranks one metric.
    public func overallLeaderboard(for footprint: ScannedFootprint, userName: String = "You") -> [OverallEntry] {
        var entries = simulatedFriends().map { friend in
            OverallEntry(id: "friend-\(friend.id)", name: friend.name, isUser: false,
                         greenScore: greenScore(friend.yearly))
        }
        entries.append(OverallEntry(id: "user", name: userName, isUser: true,
                                    greenScore: greenScore(userYearly(scanned: footprint))))
        return entries.sorted { ($0.greenScore.score, $1.id) > ($1.greenScore.score, $0.id) }
    }
}
