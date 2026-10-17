import Foundation
import SwiftData

/// SwiftData container setup (local only, spec §2).
enum Persistence {
    static let schema = Schema([StoredScan.self, CachedMetrics.self, StoredProfile.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
