import Foundation
import SwiftData
import GreenCore

/// SwiftData-backed evidence-ladder cache (spec §5.4): a hit skips resolution so the same identifier
/// always yields the same numbers. Reads and writes hop to the main context.
nonisolated struct ScanCache: ResolutionCache {
    let container: ModelContainer

    func cachedResolution(forKey key: String) async -> CachedResolution? {
        await MainActor.run { try? ScanStore(context: container.mainContext).cachedResolution(forKey: key) }
    }

    func store(_ resolution: CachedResolution, forKey key: String) async {
        await MainActor.run { try? ScanStore(context: container.mainContext).cache(resolution, forKey: key) }
    }
}
