import Foundation

/// Normalizes free-text lookup keys ("Beef Burger", "e-bike charger") to snake_case table keys.
enum ReferenceKey {
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        var pendingSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !result.isEmpty { result.append("_") }
                result.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else {
                pendingSeparator = true
            }
        }
        return result
    }

    /// Uppercase alphanumerics only, for model numbers ("UX3405MA-DB71" → "UX3405MADB71").
    static func modelKey(_ text: String) -> String {
        String(text.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}

/// Maps a canonical key plus aliases to records, with exact and token-based fallback matching.
struct AliasIndex<Record: Sendable>: Sendable {
    private var records: [String: Record] = [:]
    /// Aliases (and canonical keys) sorted longest first so "organic_cotton" beats "cotton".
    private var keysByLength: [String] = []

    init(_ entries: [(key: String, aliases: [String], record: Record)]) {
        for entry in entries {
            for name in [entry.key] + entry.aliases {
                let key = ReferenceKey.normalize(name)
                if records[key] == nil { records[key] = entry.record }
            }
        }
        keysByLength = records.keys.sorted { ($0.count, $0) > ($1.count, $1) }
    }

    var allRecords: [Record] { Array(records.values) }

    /// Exact key or alias, else the longest key whose tokens all appear in the query ("beef burger" → beef).
    func lookup(_ query: String) -> Record? {
        let key = ReferenceKey.normalize(query)
        guard !key.isEmpty else { return nil }
        if let exact = records[key] { return exact }
        let tokens = key.split(separator: "_")
        for candidate in keysByLength {
            let candidateTokens = candidate.split(separator: "_")
            if Self.containsRun(candidateTokens, in: tokens) { return records[candidate] }
        }
        return nil
    }

    private static func containsRun(_ needle: [Substring], in haystack: [Substring]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}
