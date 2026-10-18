import SwiftUI
import GreenCore

/// Leaderboard of your friends plus you, greenest first (spec §9): one metric's yearly footprints, or overall
/// GreenScores. Each person gets a circle with their initials, and the header says what the numbers stand for.
struct FriendsLeaderboard: View {
    struct Row: Identifiable {
        let id: String
        let name: String
        let isUser: Bool
        let detail: String
        let value: String
    }

    let basis: String
    /// Greenest first.
    let rows: [Row]

    /// One metric's board, from `CohortModel.leaderboard`.
    init(metric: MetricKey, entries: [LeaderboardEntry]) {
        basis = CohortMetric.basis(metric)
        rows = entries.map { entry in
            Row(id: entry.id, name: entry.name, isUser: entry.isUser,
                detail: "Greener than \(SharePercent.format(entry.greenerThan))",
                value: YearlyValue.format(entry.value, metric: metric))
        }
    }

    /// The overall board, from `CohortModel.overallLeaderboard`.
    init(overall entries: [OverallEntry]) {
        basis = "GreenScore out of 100, all four metrics"
        rows = entries.map { entry in
            Row(id: entry.id, name: entry.name, isUser: entry.isUser,
                detail: OverallWording.versusTypical(entry.greenScore.footprintRatio),
                value: "\(entry.greenScore.points)")
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friends").font(.headline)
                    Text(basis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { rank, row in
                    self.row(rank: rank + 1, row: row)
                    if rank < rows.count - 1 { Divider().padding(.leading, 78) }
                }
            }
        }
        .accessibilityIdentifier("leaderboard")
    }

    private func row(rank: Int, row: Row) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .frame(width: 22)
                .foregroundStyle(rank <= 3 ? Theme.leaf : .secondary)
            InitialsAvatar(name: row.name, isUser: row.isUser)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.subheadline.weight(row.isUser ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.value)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, row.isUser ? 6 : 0)
        .background(row.isUser ? AnyShapeStyle(Theme.leaf.opacity(0.12)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// A circle with a person's initials, tinted by a stable color derived from the name.
struct InitialsAvatar: View {
    let name: String
    var isUser = false

    private var initials: String {
        guard !isUser || name != "You" else { return "You" }
        return name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private static let palette: [Color] = [.teal, .indigo, .orange, .pink, .purple, .blue, .mint, .brown, .cyan]

    private var color: Color {
        guard !isUser else { return Theme.leaf }
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[hash % Self.palette.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: isUser ? 11 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color.gradient, in: .circle)
            .accessibilityHidden(true)
    }
}
