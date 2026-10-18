import Foundation
import Observation
import GreenCore

/// State for the alternatives screen: loading swaps, the user's picks and the greener image.
@Observable
final class AlternativesModel {
    enum Phase: Equatable {
        /// Not checked yet. Nothing is drawn, so swaps prefetched in the background appear without a loading flash.
        case pending
        case loading
        case ready
        case failed(String)
    }

    enum ImageState: Equatable {
        case idle
        case generating
        case ready(Data)
        case failed(String)
    }

    private(set) var result: ScanResult
    private(set) var phase: Phase
    private(set) var imageState: ImageState
    /// Component id → chosen alternative id.
    private(set) var selection: [UUID: UUID]
    /// Components the user deliberately kept; default picks skip them.
    private(set) var keptOriginals: Set<UUID>
    /// Component id → yearly charging carbon with and without green-hours scheduling.
    private(set) var charging: [UUID: SmartPlugAlternative.ChargingCarbon] = [:]

    /// Spec §11: the image call times out after 60 s.
    static let imageTimeout: Duration = .seconds(60)

    init(result: ScanResult) {
        self.result = result
        self.selection = result.selectedAlternatives
        self.keptOriginals = result.keptOriginals
        self.imageState = result.greenerImage.map { .ready($0) } ?? .idle
        self.phase = result.hasAlternatives ? .ready : .pending
    }

    var hasPhoto: Bool { !(result.photo ?? Data()).isEmpty }

    /// A greener picture only suits a scene: for one item or a pair the edit looks odd, so it is not offered.
    static func showsGreenerImage(for result: ScanResult) -> Bool { result.components.count > 2 }

    var showsGreenerImage: Bool { Self.showsGreenerImage(for: result) }

    func alternatives(for component: Component, plugFeatures: Bool) -> [Alternative] {
        Self.alternatives(for: component, plugFeatures: plugFeatures)
    }

    /// The swaps to offer: plug scheduling when plug features are on, product swaps that pass the GreenScore
    /// trade-off rule (scans saved before it existed may still hold others).
    static func alternatives(for component: Component, plugFeatures: Bool) -> [Alternative] {
        component.alternatives.filter { alternative in
            alternative.kind == .smartPlugScheduling
                ? plugFeatures : GreenScore.accepts(alternative, replacing: component, engine: SwapMath.engine)
        }
    }

    func pick(for component: Component) -> Alternative? {
        guard let id = selection[component.id] else { return nil }
        return component.alternatives.first { $0.id == id }
    }

    /// Selection limited to what is visible, so hidden plug swaps never count.
    func visibleSelection(plugFeatures: Bool) -> [UUID: UUID] {
        selection.filter { componentID, alternativeID in
            guard let component = result.component(withID: componentID) else { return false }
            return alternatives(for: component, plugFeatures: plugFeatures).contains { $0.id == alternativeID }
        }
    }

    // MARK: - Loading

    /// Shows the scan's swaps: saved ones, else the background prefetch (awaiting it if it is still running),
    /// then default picks and the plug rows' charging comparison.
    func load(app: AppModel) async {
        // The pushed result can be stale; a saved copy carries earlier picks and swaps.
        if let saved = app.scans.first(where: { $0.id == result.id }), saved != result, saved.hasAlternatives {
            result = saved
            selection = saved.selectedAlternatives
            keptOriginals = saved.keptOriginals
            imageState = saved.greenerImage.map { .ready($0) } ?? .idle
        }
        let before = result
        let beforeSelection = selection
        let beforeKept = keptOriginals
        if !result.hasAlternatives {
            do {
                let fetched: ScanResult
                if let ready = app.swapPrefetch.fetched(for: result) {
                    fetched = ready
                } else {
                    phase = .loading
                    fetched = try await app.swapPrefetch.swaps(for: result, app: app)
                }
                result = SwapPrefetcher.rebase(fetched, onto: result, engine: ImpactEngine(reference: app.services.reference),
                                               profile: app.profile)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }
        selection = Self.defaultPicks(for: result, selection: selection, kept: keptOriginals,
                                      plugFeatures: app.flags.plugFeaturesEnabled)
        phase = .ready
        if result != before || selection != beforeSelection || keptOriginals != beforeKept { persist(app) }
        await loadCharging(app: app)
    }

    /// Spec §7 default picks for components without one, unless the user kept the original
    /// (`SwapMath.defaultPick`: the best GreenScore among swaps that do not add carbon).
    static func defaultPicks(for result: ScanResult, selection: [UUID: UUID], kept: Set<UUID>,
                             plugFeatures: Bool) -> [UUID: UUID] {
        var picks = selection
        for component in result.components where picks[component.id] == nil && !kept.contains(component.id) {
            let options = alternatives(for: component, plugFeatures: plugFeatures)
            if let best = SwapMath.defaultPick(for: component, among: options) { picks[component.id] = best.id }
        }
        return picks
    }

    /// The plug rows' charging comparison. The grid outlook can take a while on a cold start, so the swaps show
    /// first and the chart fills in.
    private func loadCharging(app: AppModel) async {
        let charging = await SmartPlugAlternative.charging(for: result, profile: app.profile, services: app.services)
        guard !charging.isEmpty else { return }
        self.charging = charging
        var filled = false
        for index in result.components.indices where result.components[index].plugCandidate?.estimatedSavings == nil {
            guard let savings = charging[result.components[index].id]?.savings else { continue }
            result.components[index].plugCandidate?.estimatedSavings = savings
            filled = true
        }
        if filled { persist(app) }
    }

    // MARK: - Selection

    /// Picks an alternative; tapping the current pick keeps the original instead.
    func toggle(_ alternative: Alternative, for component: Component, app: AppModel) {
        if selection[component.id] == alternative.id {
            selection[component.id] = nil
            keptOriginals.insert(component.id)
        } else {
            selection[component.id] = alternative.id
            keptOriginals.remove(component.id)
        }
        if case .ready = imageState { imageState = .idle }
        result.greenerImage = nil
        persist(app)
    }

    // MARK: - Greener image

    /// Generates the greener picture for the current picks, using the background edit when it was made for
    /// exactly these picks (the defaults).
    func generateImage(app: AppModel) async {
        guard showsGreenerImage, let photo = result.photo, !photo.isEmpty else { return }
        let swaps = GreenerImagePrompt.swaps(for: result, selection: visibleSelection(plugFeatures: app.flags.plugFeaturesEnabled))
        guard let prompt = GreenerImagePrompt.make(swaps: swaps) else { return }
        imageState = .generating
        let editor = app.services.imageEditor
        let prefetched = app.swapPrefetch.image(for: result.id, prompt: prompt)
        do {
            let image: Data
            if let prefetched, let ready = try? await prefetched.value {
                image = ready
            } else {
                image = try await Self.withTimeout(Self.imageTimeout) {
                    try await editor.editImage(photo, prompt: prompt)
                }
            }
            imageState = .ready(image)
            result.greenerImage = image
            persist(app)
        } catch is CancellationError {
            imageState = .idle
        } catch {
            imageState = .failed(Self.describe(error))
        }
    }

    private func persist(_ app: AppModel) {
        result.selectedAlternatives = selection
        result.keptOriginals = keptOriginals
        app.save(result)
    }

    private static func describe(_ error: any Error) -> String {
        switch error as? GreenCoreError {
        case .timeout: "The image service took too long."
        case .missingAPIKey(let key): "Add an \(key) key in Settings to generate images."
        case .http(let status, _): "The image service returned an error (\(status))."
        default: error.localizedDescription
        }
    }

    static func withTimeout<T: Sendable>(_ limit: Duration,
                                         _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw GreenCoreError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw GreenCoreError.timeout }
            return first
        }
    }
}
