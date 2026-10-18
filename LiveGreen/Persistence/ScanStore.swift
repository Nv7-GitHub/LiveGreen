import Foundation
import SwiftData
import GreenCore

/// Typed access to scans, profile and the metrics cache on a `ModelContext`.
struct ScanStore {
    let context: ModelContext

    func allScans() throws -> [ScanResult] {
        let descriptor = FetchDescriptor<StoredScan>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try context.fetch(descriptor).map { try $0.result() }
    }

    func save(_ result: ScanResult) throws {
        let id = result.id
        if let existing = try context.fetch(FetchDescriptor<StoredScan>(predicate: #Predicate { $0.id == id })).first {
            try existing.update(from: result)
        } else {
            context.insert(try StoredScan(result: result))
        }
        try context.save()
    }

    /// Deletes the scan's row; SwiftData removes its externally stored photo and greener image with it.
    func deleteScan(id: UUID) throws {
        try context.delete(model: StoredScan.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    /// Deletes every scan, the profile and the metrics cache.
    func deleteAll() throws {
        try context.delete(model: StoredScan.self)
        try context.delete(model: StoredProfile.self)
        try context.delete(model: CachedMetrics.self)
        try context.save()
    }

    func profile() throws -> UserProfile? {
        try context.fetch(FetchDescriptor<StoredProfile>()).first?.profile()
    }

    func saveProfile(_ profile: UserProfile) throws {
        try context.delete(model: StoredProfile.self)
        context.insert(try StoredProfile(profile: profile))
        try context.save()
    }

    func cachedResolution(forKey key: String) throws -> CachedResolution? {
        try context.fetch(FetchDescriptor<CachedMetrics>(predicate: #Predicate { $0.key == key })).first?.resolution()
    }

    func cache(_ resolution: CachedResolution, forKey key: String) throws {
        try context.delete(model: CachedMetrics.self, where: #Predicate { $0.key == key })
        context.insert(try CachedMetrics(key: key, resolution: resolution))
        try context.save()
    }
}
