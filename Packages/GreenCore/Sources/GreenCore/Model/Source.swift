import Foundation

/// A citation backing a number.
public struct Source: Codable, Sendable, Hashable {
    public let title: String
    public let url: URL?
    public let tier: Tier
    /// Quoted text the value was taken from (required for researched specs).
    public let quote: String?

    public init(title: String, url: URL? = nil, tier: Tier, quote: String? = nil) {
        self.title = title
        self.url = url
        self.tier = tier
        self.quote = quote
    }
}
