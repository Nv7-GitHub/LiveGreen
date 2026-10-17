import Foundation
import GreenCore

/// Evidence-ladder cache: a hit skips resolution so the same identifier always yields the same numbers.
struct ScanCache {
    let store: ScanStore

    func lookup(_ identifiers: Identifiers) -> CachedResolution? {
        guard let key = identifiers.cacheKey else { return nil }
        return try? store.cachedResolution(forKey: key)
    }

    func remember(_ component: Component) {
        guard let key = component.identifiers.cacheKey, !component.metrics.isEmpty else { return }
        try? store.cache(CachedResolution(metrics: component.metrics, stageShares: component.stageShares), forKey: key)
    }
}
