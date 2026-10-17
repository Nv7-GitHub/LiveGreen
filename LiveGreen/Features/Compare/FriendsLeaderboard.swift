import SwiftUI
import GreenCore

/// Leaderboard of the seeded simulated network plus the user, greenest first (spec §9).
struct FriendsLeaderboard: View {
    let metric: MetricKey
    /// Greenest first, from `CohortModel.leaderboard`.
    let entries: [LeaderboardEntry]
    /// Avatar SF Symbol per entry id.
    let avatarSymbols: [String: String]

    private func symbol(for entry: LeaderboardEntry) -> String {
        entry.isUser ? "person.crop.circle.fill" : (avatarSymbols[entry.id] ?? "person.fill")
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Leaderboard").font(.headline)
                    Spacer()
                    Label("Simulated network", systemImage: "person.3.sequence")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(Theme.warning.opacity(0.25)), in: .capsule)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { rank, entry in
                    row(rank: rank + 1, entry: entry)
                }
                Text("Friends are sampled from your modeled peer cohort with a fixed seed. They are not real people.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(rank: Int, entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Image(systemName: symbol(for: entry))
                .font(.body)
                .frame(width: 34, height: 34)
                .foregroundStyle(entry.isUser ? .white : Theme.leaf)
                .background(entry.isUser ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.mint.opacity(0.3)), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.subheadline.weight(entry.isUser ? .bold : .regular))
                Text("Greener than \(SharePercent.format(entry.greenerThan))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(YearlyValue.format(entry.value, metric: metric))
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
