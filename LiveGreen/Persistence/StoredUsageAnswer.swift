import Foundation
import SwiftData

/// The user's rate a week for one kind of item (`UsageDefaults.kindKey`, e.g. "food:latte"): servings for food, uses
/// for packaging and personal care. Later scans of that kind start from it instead of the typical week.
@Model
final class StoredUsageAnswer {
    @Attribute(.unique) var key: String
    var perWeek: Double
    var updatedAt: Date

    init(key: String, perWeek: Double) {
        self.key = key
        self.perWeek = perWeek
        updatedAt = Date()
    }
}
