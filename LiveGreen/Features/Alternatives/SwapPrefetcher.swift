import Foundation
import GreenCore

extension ScanResult {
    /// Whether greener swaps have been fetched for this scan.
    var hasAlternatives: Bool { components.contains { !$0.alternatives.isEmpty } }
}

/// Greener swaps fetched in the background as soon as a scan exists, with nothing on screen, so "See greener
/// swaps" opens on finished results. A request while the fetch runs awaits the same task, never a second call;
/// a failed fetch is dropped so the swaps screen can try again.
///
/// Entries are keyed by scan id and what was scanned (component ids, names, categories, identifiers and
/// quantities), so a scan whose items changed fetches again. Usage answers on the results screen change how
/// much, not what, so they reuse the swaps; `rebase` carries the new usage over. When the scan shows a greener
/// image (more than two items), the image for the default picks is prefetched once the swaps arrive.
final class SwapPrefetcher {
    private struct Identity: Hashable {
        struct Item: Hashable {
            var id: UUID
            var name: String
            var category: GreenCore.Category
            var identifiers: Identifiers
            var quantities: Quantities
        }

        var items: [Item]

        init(_ result: ScanResult) {
            items = result.components.map {
                Item(id: $0.id, name: $0.name, category: $0.category, identifiers: $0.identifiers, quantities: $0.quantities)
            }
        }
    }

    private struct Entry {
        var identity: Identity
        var token: UUID
        var swaps: Task<ScanResult, any Error>
        var fetched: ScanResult?
        /// The image-edit prompt for the default picks and its running or finished edit.
        var image: (prompt: String, task: Task<Data, any Error>)?

        func cancel() {
            swaps.cancel()
            image?.task.cancel()
        }
    }

    private var entries: [UUID: Entry] = [:]

    /// Starts fetching swaps for a scan, unless it has them or a fetch for the same items exists.
    func prefetch(_ result: ScanResult, app: AppModel) {
        guard !result.components.isEmpty, !result.hasAlternatives else { return }
        let identity = Identity(result)
        if entries[result.id]?.identity == identity { return }
        entries[result.id]?.cancel()
        let token = UUID()
        let coordinator = app.makeScanCoordinator(mode: result.mode)
        let plugFeatures = app.flags.plugFeaturesEnabled
        let editor = app.services.imageEditor
        let swaps = Task { [weak self] () throws -> ScanResult in
            do {
                let fetched = try await coordinator.suggestAlternatives(for: result)
                self?.didFetch(fetched, token: token, plugFeatures: plugFeatures, editor: editor)
                return fetched
            } catch {
                self?.drop(result.id, token: token)
                throw error
            }
        }
        entries[result.id] = Entry(identity: identity, token: token, swaps: swaps)
    }

    /// Swaps already fetched for this scan's items, without waiting.
    func fetched(for result: ScanResult) -> ScanResult? {
        guard let entry = entries[result.id], entry.identity == Identity(result) else { return nil }
        return entry.fetched
    }

    /// The swaps for a scan: the finished or running fetch for its items, else a new one.
    func swaps(for result: ScanResult, app: AppModel) async throws -> ScanResult {
        prefetch(result, app: app)
        guard let entry = entries[result.id] else {
            return try await app.makeScanCoordinator(mode: result.mode).suggestAlternatives(for: result)
        }
        return try await entry.swaps.value
    }

    /// The prefetched greener image for exactly this edit, if one was started.
    func image(for scanID: UUID, prompt: String) -> Task<Data, any Error>? {
        guard let image = entries[scanID]?.image, image.prompt == prompt else { return nil }
        return image.task
    }

    /// Forgets everything, e.g. when the services change.
    func reset() {
        entries.values.forEach { $0.cancel() }
        entries = [:]
    }

    private func didFetch(_ fetched: ScanResult, token: UUID, plugFeatures: Bool, editor: any ImageEditor) {
        guard entries[fetched.id]?.token == token else { return }
        entries[fetched.id]?.fetched = fetched
        guard AlternativesModel.showsGreenerImage(for: fetched), let photo = fetched.photo, !photo.isEmpty else { return }
        let picks = AlternativesModel.defaultPicks(for: fetched, selection: fetched.selectedAlternatives,
                                                   kept: fetched.keptOriginals, plugFeatures: plugFeatures)
        guard let prompt = GreenerImagePrompt.make(swaps: GreenerImagePrompt.swaps(for: fetched, selection: picks)) else {
            return
        }
        let task = Task {
            try await AlternativesModel.withTimeout(AlternativesModel.imageTimeout) {
                try await editor.editImage(photo, prompt: prompt)
            }
        }
        entries[fetched.id]?.image = (prompt, task)
    }

    private func drop(_ scanID: UUID, token: UUID) {
        if entries[scanID]?.token == token { entries[scanID] = nil }
    }

    /// Moves swaps fetched for an earlier copy of a scan onto the current one. Usage answered since then changes
    /// how much, not what: a swap that shared the original's usage takes the new usage too and is re-derived
    /// locally (electronics' yearly electricity and use-phase carbon), the plug option is rebuilt from the
    /// current item, and the GreenScore trade-off rule runs again.
    static func rebase(_ fetched: ScanResult, onto current: ScanResult, engine: ImpactEngine,
                       profile: UserProfile) -> ScanResult {
        var updated = current
        for index in updated.components.indices {
            let component = updated.components[index]
            guard let then = fetched.component(withID: component.id) else { continue }
            let moved = then.alternatives.map { alternative -> Alternative in
                if alternative.kind == .smartPlugScheduling { return .smartPlugScheduling(for: component) }
                guard let usage = component.usage, usage != then.usage, alternative.usage == then.usage else {
                    return alternative
                }
                var swap = alternative
                swap.usage = usage
                swap.metrics = engine.applyingUsage(usage, to: alternative.asComponent(replacing: then), profile: profile).metrics
                return swap
            }
            updated.components[index].alternatives = GreenScore.ranked(moved, replacing: component, engine: engine)
        }
        return updated
    }
}
