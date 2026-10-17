import SwiftUI
import GreenCore

/// Leaderboard of your friends plus you, greenest first (spec §9). Each person gets a circle with their
/// initials. The friends are a simulated network, and the header says so.
struct FriendsLeaderboard: View {
    let metric: MetricKey
    /// Greenest first, from `CohortModel.leaderboard`.
    let entries: [LeaderboardEntry]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friends").font(.headline)
                    Text("Simulated network · \(CohortMetric.basis(metric).lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { rank, entry in
                    row(rank: rank + 1, entry: entry)
                    if rank < entries.count - 1 { Divider().padding(.leading, 78) }
                }
            }
        }
        .accessibilityIdentifier("leaderboard")
    }

    private func row(rank: Int, entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .frame(width: 22)
                .foregroundStyle(rank <= 3 ? Theme.leaf : .secondary)
            InitialsAvatar(name: entry.name, isUser: entry.isUser)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.subheadline.weight(entry.isUser ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Greener than \(SharePercent.format(entry.greenerThan))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(YearlyValue.format(entry.value, metric: metric))
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, entry.isUser ? 6 : 0)
        .background(entry.isUser ? AnyShapeStyle(Theme.leaf.opacity(0.12)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// A circle with a person's initials, tinted by a stable color derived from the name.
struct InitialsAvatar: View {
    let name: String
    var isUser = false

    private var initials: String {
        guard !isUser else { return "You" }
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
