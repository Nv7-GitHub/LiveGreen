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

    init(services: ServiceContainer, profile: UserProfile, mode: ScanMode, cache: (any ResolutionCache)? = nil) {
        self.services = services
        self.profile = profile
        self.mode = mode
        pipeline = services.pipeline(profile: profile, cache: cache)
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

    /// Re-runs the engine locally with question answers (spec §5.5).
    func applying(_ answers: [QuestionAnswer], to result: ScanResult) -> ScanResult {
        pipeline.applying(answers.map { ($0.question.componentID, $0.option) }, to: result)
    }
}
