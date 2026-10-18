import Foundation
import Observation
import SwiftData
import GreenCore

/// The notes the user left on scans, newest first, for the results card, Settings and the identify hints.
@Observable
final class FeedbackStore {
    private(set) var notes: [ScanFeedback] = []
    @ObservationIgnored private let context: ModelContext

    /// The most notes a scan considers; `ScanFeedback.relevant` sends identify a few of them.
    static let hintPool = 50

    init(context: ModelContext) {
        self.context = context
        let descriptor = FetchDescriptor<StoredFeedback>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        notes = ((try? context.fetch(descriptor)) ?? []).map(\.feedback)
    }

    /// Recent notes for the next scan's identify call.
    var identifyHints: [ScanFeedback] { Array(notes.prefix(Self.hintPool)) }

    func notes(forScan id: UUID) -> [ScanFeedback] {
        notes.filter { $0.scanID == id }
    }

    /// Saves a note on `scan`, recording what it identified. Blank notes are ignored.
    func add(_ text: String, on scan: ScanResult) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let feedback = ScanFeedback(note: trimmed, on: scan)
        context.insert(StoredFeedback(feedback))
        try context.save()
        notes.insert(feedback, at: 0)
    }

    func delete(id: UUID) throws {
        try context.delete(model: StoredFeedback.self, where: #Predicate { $0.id == id })
        try context.save()
        notes.removeAll { $0.id == id }
    }

    func deleteAll() throws {
        try context.delete(model: StoredFeedback.self)
        try context.save()
        notes = []
    }
}
