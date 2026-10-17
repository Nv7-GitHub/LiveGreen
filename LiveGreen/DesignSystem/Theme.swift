import SwiftUI
import GreenCore

/// LiveGreen palette and shared constants.
enum Theme {
    /// Brand green (asset AccentColor; adapts to Dark Mode).
    static let accent = Color.accentColor
    static let leaf = Color(red: 0.16, green: 0.62, blue: 0.38)
    static let mint = Color(red: 0.55, green: 0.86, blue: 0.68)
    static let moss = Color(red: 0.29, green: 0.42, blue: 0.24)
    static let warning = Color.orange
    static let danger = Color(red: 0.86, green: 0.30, blue: 0.24)

    static let cardCornerRadius: CGFloat = 24
    static let hotspotCornerRadius: CGFloat = 14

    /// Hotspot tint for a component's share of scan carbon: green (small) → amber → red (dominant).
    static func carbonShareTint(_ share: Double) -> Color {
        let s = min(max(share, 0), 1)
        switch s {
        case ..<0.15: return leaf
        case ..<0.4: return .yellow
        case ..<0.65: return .orange
        default: return danger
        }
    }
}

extension Tier {
    /// Badge color: T1 green → T4 gray.
    var color: Color {
        switch self {
        case .exactRecord: Theme.leaf
        case .researchedSpec: .teal
        case .factorModel: .orange
        case .estimate: .gray
        }
    }
}
