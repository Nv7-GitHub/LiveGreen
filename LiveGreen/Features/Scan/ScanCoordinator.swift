import Foundation
import Observation
import GreenCore

/// Runs the scan pipeline (spec §5) and reports progress as `PipelineEvent`s.
protocol ScanCoordinating: AnyObject {
    /// Streams pipeline progress; the last event of a successful run is `.completed(ScanResult)`.
    func scan(image: Data, hints: OCRHints) -> AsyncThrowingStream<PipelineEvent, Error>
    /// The result of the most recent successful scan.
    var latestResult: ScanResult? { get }
}

/// Binds GreenCore's `ScanPipeline` to the current services, profile and SwiftData cache.
@Observable
final class ScanCoordinator: ScanCoordinating {
    let services: ServiceContainer
    let profile: UserProfile
    let mode: ScanMode
    @ObservationIgnored let pipeline: ScanPipeline
    private(set) var latestResult: ScanResult?

    /// - Parameter feedback: notes from earlier scans; identify gets the most relevant few as weak hints.
    init(services: ServiceContainer, profile: UserProfile, mode: ScanMode, cache: (any ResolutionCache)? = nil,
         feedback: [ScanFeedback] = []) {
        self.services = services
        self.profile = profile
        self.mode = mode
        var pipeline = services.pipeline(profile: profile, cache: cache)
        pipeline.feedback = feedback
        self.pipeline = pipeline
    }

    func scan(image: Data, hints: OCRHints) -> AsyncThrowingStream<PipelineEvent, Error> {
        let pipeline = pipeline
        let mode = mode
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await pipeline.run(image: image, hints: hints, mode: mode) { continuation.yield($0) }
                    latestResult = result
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Asks for greener alternatives and resolves them through the same ladder as the originals (spec §7).
    func suggestAlternatives(for result: ScanResult) async throws -> ScanResult {
        let updated = try await pipeline.suggestAlternatives(for: result)
        latestResult = updated
        return updated
    }

    /// Re-resolves items whose detail questions were answered before the results (T4 → factor model), on-device.
    func refining(_ result: ScanResult, specAnswers: [SpecAnswer]) async -> ScanResult {
        let refined = await pipeline.refining(result, specAnswers: specAnswers)
        latestResult = refined
        return refined
    }

    /// Re-runs the engine locally with question answers (spec §5.5).
    func applying(_ answers: [QuestionAnswer], to result: ScanResult) -> ScanResult {
        pipeline.applying(answers.map { ($0.question.componentID, $0.option) }, to: result)
    }

    /// Re-runs the engine after the user edits one usage field of a component.
    func applying(usage field: UsageField, value: Double, to componentID: UUID, in result: ScanResult) -> ScanResult {
        guard let component = result.component(withID: componentID) else { return result }
        let edits = ImpactEngine().usageEdits(field, value, for: component)
        return pipeline.applying(edits.map { (componentID, $0) }, to: result)
    }

    /// The user said whether one item is theirs ("Not mine", "It's mine"; nil restores the scan's guess): the totals
    /// are recomputed without the items left out.
    func markingOwned(_ owned: Bool?, componentID: UUID, in result: ScanResult) -> ScanResult {
        var updated = result
        updated.markOwned(owned, componentID: componentID, engine: pipeline.engine)
        return updated
    }

    /// "Which is yours?": exactly `owned` are the user's.
    func markingOwned(only owned: Set<UUID>, in result: ScanResult) -> ScanResult {
        var updated = result
        updated.markOwned(only: owned, engine: pipeline.engine)
        return updated
    }
}
