import Foundation

/// Scores how well a scanned model number matches an ENERGY STAR model entry. ENERGY STAR lists
/// base models with wildcards ("DLGX3371*", "AREF18**", "NS-32F2#2") and regional suffixes
/// ("E2225Hf" for "E2225H"), so exact string equality is too strict.
enum ModelNumberMatcher {
    enum Score: Int, Comparable {
        case none = 0, variant, wildcard, exact
        static func < (lhs: Score, rhs: Score) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Uppercased alphanumerics; wildcard characters are kept when `keepWildcards` is set.
    static func normalize(_ model: String, keepWildcards: Bool = false) -> String {
        String(model.uppercased().filter { $0.isLetter || $0.isNumber || (keepWildcards && "*#?".contains($0)) })
    }

    static func score(query: String, candidate: String) -> Score {
        let target = normalize(query)
        let pattern = normalize(candidate, keepWildcards: true)
        guard target.count >= 3, !pattern.isEmpty else { return .none }
        if pattern == target { return .exact }
        if pattern.contains(where: { "*#?".contains($0) }), wildcardMatches(pattern: Array(pattern), text: Array(target)) {
            return .wildcard
        }
        let plain = normalize(candidate)
        let (short, long) = plain.count <= target.count ? (plain, target) : (target, plain)
        if short.count >= 4, long.hasPrefix(short), long.count - short.count <= 3 { return .variant }
        return .none
    }

    /// Best score over every model string in a record (`additional_model_information` holds
    /// comma/semicolon-separated variant lists).
    static func bestScore(query: String, candidates: [String]) -> Score {
        candidates
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",;")) }
            .map { score(query: query, candidate: $0) }
            .max() ?? .none
    }

    /// `*` matches any run (including empty); `#` and `?` match exactly one character.
    static func wildcardMatches(pattern: [Character], text: [Character]) -> Bool {
        var memo: [Int: Bool] = [:]
        func match(_ p: Int, _ t: Int) -> Bool {
            let key = p * (text.count + 1) + t
            if let cached = memo[key] { return cached }
            let result: Bool
            if p == pattern.count {
                result = t == text.count
            } else if pattern[p] == "*" {
                result = match(p + 1, t) || (t < text.count && match(p, t + 1))
            } else if t < text.count, pattern[p] == "#" || pattern[p] == "?" || pattern[p] == text[t] {
                result = match(p + 1, t + 1)
            } else {
                result = false
            }
            memo[key] = result
            return result
        }
        return match(0, 0)
    }

    /// SoQL `LIKE` pattern for the leading part of the model: selective enough to keep results small,
    /// while `%` between characters tolerates punctuation ("NS-32F2…" vs "NS32F2…") and the shortened
    /// prefix tolerates suffix variants and trailing wildcards in the stored value.
    static func likePattern(for model: String) -> String? {
        let cleaned = normalize(model)
        guard cleaned.count >= 3 else { return nil }
        let prefix = cleaned.prefix(max(4, cleaned.count - 3))
        return "%" + prefix.map(String.init).joined(separator: "%") + "%"
    }
}
