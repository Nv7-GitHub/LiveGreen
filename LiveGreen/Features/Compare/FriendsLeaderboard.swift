import SwiftUI
import GreenCore

/// Leaderboard of the seeded simulated network plus the user, greenest first (spec §9).
struct FriendsLeaderboard: View {
    let metric: MetricKey
    let friends: [CohortFriend]
    let userValue: Double
    let cohort: any CohortComparing

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let value: Double
        let isUser: Bool
    }

    private var entries: [Entry] {
        let others = friends.compactMap { friend in
            friend.footprints[metric].map {
                Entry(id: "friend-\(friend.id)", name: friend.name, symbol: friend.avatarSymbol, value: $0, isUser: false)
            }
        }
        let user = Entry(id: "you", name: "You", symbol: "person.crop.circle.fill", value: userValue, isUser: true)
        return (others + [user]).sorted { $0.value < $1.value }
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

    private func row(rank: Int, entry: Entry) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Image(systemName: entry.symbol)
                .font(.body)
                .frame(width: 34, height: 34)
                .foregroundStyle(entry.isUser ? .white : Theme.leaf)
                .background(entry.isUser ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.mint.opacity(0.3)), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.subheadline.weight(entry.isUser ? .bold : .regular))
                Text("Greener than \(SharePercent.format(cohort.greenerThan(for: metric, value: entry.value)))")
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
