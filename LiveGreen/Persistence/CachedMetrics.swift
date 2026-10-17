import Foundation
import SwiftData
import GreenCore

/// Resolution cache keyed by `Identifiers.cacheKey` (GTIN or brand|model).
@Model
final class CachedMetrics {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date

    init(key: String, resolution: CachedResolution) throws {
        self.key = key
        self.payload = try JSONEncoder().encode(resolution)
        self.updatedAt = Date()
    }

    func resolution() throws -> CachedResolution {
        try JSONDecoder().decode(CachedResolution.self, from: payload)
    }
}
