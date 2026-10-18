import SwiftUI
import GreenCore

/// Top of the Leaderboard: your (pretend) LiveGreen account and where you stand against everyone else on the
/// overall board: your rank and the next person to beat.
struct AccountCard: View {
    let name: String
    /// The overall board, greenest first; empty while it loads or before anything is scanned.
    let overall: [OverallEntry]

    /// A handle derived from the name, e.g. "Ada Lovelace" → "@adalovelace".
    private var handle: String {
        "@" + name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private var rankIndex: Int? { overall.firstIndex(where: \.isUser) }

    /// "12 pts behind Vishnu" for the person just above you, or a first-place line.
    private var standing: String? {
        guard let index = rankIndex else { return nil }
        guard index > 0 else { return "You're in 1st place. Hold it!" }
        let rival = overall[index - 1]
        let gap = max(rival.greenScore.points - overall[index].greenScore.points, 0)
        let first = rival.name.split(separator: " ").first.map(String.init) ?? rival.name
        return gap == 0 ? "Tied with \(first). Scan to pull ahead" : "\(gap) pts behind \(first). Catch up!"
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                InitialsAvatar(name: name, isUser: true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(name).font(.headline).lineLimit(1)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.leaf)
                    }
                    Text(handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let standing {
                        Text(standing)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.leaf)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer()
                if let rankIndex {
                    VStack(spacing: 0) {
                        Text("#\(rankIndex + 1)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(rankIndex < 3 ? Theme.leaf : .primary)
                        Text("of \(overall.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("leaderboard.account")
    }
}

#Preview {
    AccountCard(name: "Ada Lovelace", overall: []).padding()
}
