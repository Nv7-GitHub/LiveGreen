import Foundation
import SwiftData
import GreenCore

/// A note the user left on a scan, with what that scan identified (`ScanFeedback`). Kept apart from the scan so
/// it outlives a deleted scan as identify context; Settings → Scan feedback manages the notes.
@Model
final class StoredFeedback {
    @Attribute(.unique) var id: UUID
    var scanID: UUID
    var date: Date
    var note: String
    var identifiedItems: [String]
    /// `Category` raw values.
    var categories: [String]

    init(_ feedback: ScanFeedback) {
        id = feedback.id
        scanID = feedback.scanID
        date = feedback.date
        note = feedback.note
        identifiedItems = feedback.identifiedItems
        categories = feedback.categories.map(\.rawValue)
    }

    var feedback: ScanFeedback {
        ScanFeedback(id: id, scanID: scanID, date: date, note: note, identifiedItems: identifiedItems,
                     categories: categories.compactMap(Category.init(rawValue:)))
    }
}
