import Foundation
import Observation
import GreenCore

/// State for the alternatives screen: loading swaps, the user's picks and the greener image.
@Observable
final class AlternativesModel {
    enum Phase: Equatable {
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
        self.phase = result.components.contains { !$0.alternatives.isEmpty } ? .ready : .loading
    }

    var hasPhoto: Bool { !(result.photo ?? Data()).isEmpty }

    func alternatives(for component: Component, plugFeatures: Bool) -> [Alternative] {
        component.alternatives.filter { plugFeatures || $0.kind != .smartPlugScheduling }
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

    /// Suggests and resolves alternatives unless the scan already has them, then adds plug options.
    func load(app: AppModel) async {
        // The pushed result can be stale; a saved copy carries earlier picks and swaps.
        if let saved = app.scans.first(where: { $0.id == result.id }), saved != result,
           saved.components.contains(where: { !$0.alternatives.isEmpty }) {
            result = saved
            selection = saved.selectedAlternatives
            keptOriginals = saved.keptOriginals
            imageState = saved.greenerImage.map { .ready($0) } ?? .idle
        }
        let before = result
        let beforeSelection = selection
        let beforeKept = keptOriginals
        var working = result
        if !working.components.contains(where: { !$0.alternatives.isEmpty }) {
            phase = .loading
            do {
                working = try await app.makeScanCoordinator(mode: result.mode).suggestAlternatives(for: working)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }
        let (withPlugs, charging) = await SmartPlugAlternative.attach(to: working, profile: app.profile,
                                                                      services: app.services)
        self.charging = charging
        result = withPlugs
        applyDefaultPicks(plugFeatures: app.flags.plugFeaturesEnabled)
        phase = .ready
        if result != before || selection != beforeSelection || keptOriginals != beforeKept { persist(app) }
    }

    /// Spec §7: each component defaults to its biggest carbon saving, unless the user kept the original.
    private func applyDefaultPicks(plugFeatures: Bool) {
        for component in result.components where selection[component.id] == nil && !keptOriginals.contains(component.id) {
            let options = alternatives(for: component, plugFeatures: plugFeatures)
            if let best = SwapMath.defaultPick(for: component, among: options) { selection[component.id] = best.id }
        }
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

    func generateImage(app: AppModel) async {
        guard let photo = result.photo, !photo.isEmpty else { return }
        let swaps = GreenerImagePrompt.swaps(for: result, selection: visibleSelection(plugFeatures: app.flags.plugFeaturesEnabled))
        guard let prompt = GreenerImagePrompt.make(swaps: swaps) else { return }
        imageState = .generating
        let editor = app.services.imageEditor
        do {
            let image = try await Self.withTimeout(Self.imageTimeout) {
                try await editor.editImage(photo, prompt: prompt)
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

    private static func withTimeout<T: Sendable>(_ limit: Duration,
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
