import Foundation

/// A note the user left on a scan in their own words ("the TV was actually a large monitor"), kept with what
/// that scan identified. Later identify calls get a few of them as weak hints (`promptSection`), never as rules.
public struct ScanFeedback: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// The scan the note was left on.
    public var scanID: UUID
    public var date: Date
    public var note: String
    /// Names of the items that scan identified, most significant first, e.g. ["TV", "Soundbar"].
    public var identifiedItems: [String]
    /// Categories of those items, without duplicates.
    public var categories: [Category]

    public init(id: UUID = UUID(), scanID: UUID, date: Date = Date(), note: String, identifiedItems: [String] = [],
                categories: [Category] = []) {
        self.id = id
        self.scanID = scanID
        self.date = date
        self.note = note
        self.identifiedItems = identifiedItems
        self.categories = categories
    }

    /// A note on `scan`, recording the items it identified so later scans can see what the note corrects.
    public init(note: String, on scan: ScanResult, date: Date = Date()) {
        var categories: [Category] = []
        for component in scan.components where !categories.contains(component.category) {
            categories.append(component.category)
        }
        self.init(scanID: scan.id, date: date, note: note, identifiedItems: scan.components.map(\.name),
                  categories: categories)
    }

    /// Orders notes for an identify call, best first: notes whose scan looks like this one, then the newest.
    /// Before identify the only clues are the on-device hints, so a note scores for words it (or its items)
    /// shares with the label text, and for a category the kinds of hints suggest (`likelyCategories`).
    /// Repeated notes count once.
    public static func relevant(_ notes: [ScanFeedback], to hints: OCRHints, limit: Int = 5) -> [ScanFeedback] {
        let hintWords = words(in: hints.textLines + hints.modelNumbers)
        let likely = likelyCategories(for: hints)
        func score(_ note: ScanFeedback) -> Int {
            let shared = hintWords.intersection(words(in: [note.note] + note.identifiedItems)).count
            return shared * 2 + (likely.isDisjoint(with: note.categories) ? 0 : 1)
        }
        var seen = Set<String>()
        let unique = notes.sorted { $0.date > $1.date }.filter {
            seen.insert($0.note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)).inserted
        }
        return Array(unique.map { (note: $0, score: score($0)) }
            .sorted { ($0.score, $0.note.date) > ($1.score, $1.note.date) }
            .prefix(max(limit, 0))
            .map(\.note))
    }

    /// Categories a frame's hints point to: wattages and model numbers are printed on electronics, fiber
    /// percentages on clothing, resin codes on packaging, and barcodes on packaged food and toiletries.
    static func likelyCategories(for hints: OCRHints) -> Set<Category> {
        var categories = Set<Category>()
        if !hints.wattages.isEmpty || !hints.modelNumbers.isEmpty { categories.insert(.electronic) }
        if !hints.fiberPercentages.isEmpty { categories.insert(.clothing) }
        if !hints.resinCodes.isEmpty { categories.insert(.packaging) }
        if !hints.gtins.isEmpty { categories.formUnion([.food, .packaging, .personalCare]) }
        return categories
    }

    /// Lowercased words of two or more characters ("TV" counts), without filler that every note shares.
    static func words(in texts: [String]) -> Set<String> {
        let filler: Set<String> = ["an", "as", "at", "be", "by", "is", "it", "its", "in", "me", "my", "no", "of", "on",
                                   "or", "so", "to", "up", "we", "the", "and", "was", "were", "not", "but", "for",
                                   "with", "this", "that", "you", "your", "are", "actually", "really", "just",
                                   "scan", "scanned", "item", "items"]
        return Set(texts.flatMap { $0.lowercased().split { !$0.isLetter && !$0.isNumber } }
            .map(String.init)
            .filter { $0.count >= 2 && !filler.contains($0) })
    }
}
