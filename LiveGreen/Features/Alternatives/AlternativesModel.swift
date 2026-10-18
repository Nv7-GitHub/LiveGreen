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
    /// trade-off rule (scans saved before it existed may still hold others). None for an item the scan does not
    /// count (`Component.isTotaled`), even if its swaps were fetched before the user said it is not theirs.
    static func alternatives(for component: Component, plugFeatures: Bool) -> [Alternative] {
        guard component.isTotaled else { return [] }
        return component.alternatives.filter { alternative in
            alternative.kind == .smartPlugScheduling
                ? plugFeatures : GreenScore.accepts(alternative, replacing: component, engine: SwapMath.engine)
        }
    }

    /// Items offered exactly the same swaps (same category, the same names in the same order) share one card, so a
    /// shared bike room is one "Buy a used bicycle" card, not four. Groups keep the given order; the first item of
    /// each leads. Items with nothing to offer are left out.
    static func swapGroups(_ components: [Component], plugFeatures: Bool) -> [[Component]] {
        var groups: [[Component]] = []
        var positions: [String: Int] = [:]
        for component in components {
            let options = alternatives(for: component, plugFeatures: plugFeatures)
            guard !options.isEmpty else { continue }
            let key = ([component.category.rawValue] + options.map { $0.name.lowercased() }).joined(separator: "|")
            if let position = positions[key] {
                groups[position].append(component)
            } else {
                positions[key] = groups.count
                groups.append([component])
            }
        }
        return groups
    }

    /// The member's own alternative with the same name as one of the lead's.
    static func matching(_ alternative: Alternative, in member: Component) -> Alternative? {
        member.alternatives.first { $0.name.lowercased() == alternative.name.lowercased() && $0.kind == alternative.kind }
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
    /// Items sharing a card take the lead item's pick, so the card and the savings agree.
    static func defaultPicks(for result: ScanResult, selection: [UUID: UUID], kept: Set<UUID>,
                             plugFeatures: Bool) -> [UUID: UUID] {
        var picks = selection
        for component in result.components where picks[component.id] == nil && !kept.contains(component.id) {
            let options = alternatives(for: component, plugFeatures: plugFeatures)
            if let best = SwapMath.defaultPick(for: component, among: options) { picks[component.id] = best.id }
        }
        let ordered = SwapMath.byYearlySaving(result.components) { alternatives(for: $0, plugFeatures: plugFeatures) }
        for group in swapGroups(ordered, plugFeatures: plugFeatures) where group.count > 1 {
            let leadPick = picks[group[0].id].flatMap { id in group[0].alternatives.first { $0.id == id } }
            for member in group.dropFirst() where !kept.contains(member.id) {
                picks[member.id] = leadPick.flatMap { matching($0, in: member)?.id }
            }
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

    /// Picks an alternative; tapping the current pick keeps the original instead. Items sharing the card (`others`)
    /// take the same-named swap, or keep their originals with the lead.
    func toggle(_ alternative: Alternative, for component: Component, others: [Component] = [], app: AppModel) {
        let keeping = selection[component.id] == alternative.id
        let members: [(Component, Alternative?)] = [(component, alternative)]
            + others.map { ($0, Self.matching(alternative, in: $0)) }
        for (member, swap) in members {
            if keeping || swap == nil {
                selection[member.id] = nil
                keptOriginals.insert(member.id)
            } else {
                selection[member.id] = swap?.id
                keptOriginals.remove(member.id)
            }
        }
        if case .ready = imageState { imageState = .idle }
        result.greenerImage = nil
        persist(app)
    }

    // MARK: - Greener image

    /// The picture is on screen for the current picks, so the button offers another version instead (G1).
    var hasImage: Bool {
        if case .ready = imageState { return true }
        return false
    }

    /// Generates the greener picture for the current picks, using the background edit when it was made for
    /// exactly these picks (the defaults), unless a `fresh` version is asked for. The edit is put on the photo's
    /// own frame (`GreenerImageFit`) so the before/after halves line up.
    func generateImage(app: AppModel, fresh: Bool = false) async {
        guard showsGreenerImage, let photo = result.photo, !photo.isEmpty else { return }
        let swaps = GreenerImagePrompt.swaps(for: result, selection: visibleSelection(plugFeatures: app.flags.plugFeaturesEnabled))
        guard let prompt = GreenerImagePrompt.make(swaps: swaps) else { return }
        imageState = .generating
        let editor = app.services.imageEditor
        let prefetched = fresh ? nil : app.swapPrefetch.image(for: result.id, prompt: prompt)
        do {
            let edit: Data
            if let prefetched, let ready = try? await prefetched.value {
                edit = ready
            } else {
                edit = try await Self.withTimeout(Self.imageTimeout) {
                    try await editor.editImage(photo, prompt: prompt)
                }
            }
            let image = await Self.fitted(edit, to: photo)
            imageState = .ready(image)
            result.greenerImage = image
            persist(app)
        } catch is CancellationError {
            imageState = .idle
        } catch {
            imageState = .failed(Self.describe(error))
        }
    }

    /// The edit on the photo's frame, decoded and redrawn off the main actor; the edit as it came if it can't be read.
    static func fitted(_ edit: Data, to photo: Data) async -> Data {
        await Task.detached(priority: .userInitiated) { GreenerImageFit.fitted(edit, to: photo) ?? edit }.value
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
