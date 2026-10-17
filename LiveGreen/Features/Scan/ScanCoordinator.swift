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

@Observable
final class ScanCoordinator: ScanCoordinating {
    let services: ServiceContainer
    let profile: UserProfile
    let mode: ScanMode
    @ObservationIgnored private let cache: ScanCache?
    private(set) var latestResult: ScanResult?

    init(services: ServiceContainer, profile: UserProfile, mode: ScanMode, cache: ScanCache? = nil) {
        self.services = services
        self.profile = profile
        self.mode = mode
        self.cache = cache
    }

    func scan(image: Data, hints: OCRHints) -> AsyncThrowingStream<PipelineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await run(image: image, hints: hints) { continuation.yield($0) }
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
        let suggestions = try await services.alternatives.suggestAlternatives(for: result.components, profile: profile)
        let ladder = EvidenceLadder(resolvers: services.resolvers)
        var updated = result
        for suggestion in suggestions {
            guard let index = updated.components.firstIndex(where: { $0.id == suggestion.componentID }) else { continue }
            var resolved: [Alternative] = []
            for alternative in suggestion.alternatives {
                let asComponent = Component(id: alternative.id, name: alternative.name, category: alternative.category,
                                            identifiers: alternative.identifiers, quantities: alternative.quantities,
                                            usage: alternative.usage, fallbackEstimates: alternative.fallbackEstimates)
                var filled = alternative
                filled.metrics = await ladder.resolve(asComponent, profile: profile).metrics
                resolved.append(filled)
            }
            updated.components[index].alternatives = resolved
        }
        latestResult = updated
        return updated
    }

    // MARK: - Pipeline

    private func run(image: Data, hints: OCRHints, emit: @escaping @Sendable (PipelineEvent) -> Void) async throws -> ScanResult {
        emit(.stepStarted(.readingLabels))
        // The capture views run the on-device Vision pre-pass and hand over `hints`.
        emit(.stepFinished(.readingLabels))

        emit(.stepStarted(.identifying))
        let response = try await identifyWithRetry(image: image, hints: hints)
        var components = response.components.map(makeComponent)
        emit(.componentsIdentified(components))
        emit(.stepFinished(.identifying))

        for (index, component) in components.enumerated() {
            if let cached = cache?.lookup(component.identifiers) {
                components[index].metrics = cached.metrics
                components[index].stageShares = cached.stageShares
            }
        }

        let phases: [(PipelineStep, ClosedRange<Tier>)] = [
            (.lookingUpRecords, .exactRecord ... .exactRecord),
            (.researchingSpecs, .researchedSpec ... .researchedSpec),
            (.computing, .factorModel ... .estimate),
        ]
        for (step, tiers) in phases {
            emit(.stepStarted(step))
            let ladder = EvidenceLadder(resolvers: services.resolvers.filter { tiers.contains($0.tier) })
            components = await resolveAll(components, ladder: ladder, emit: emit)
            emit(.stepFinished(step))
        }
        components.forEach { cache?.remember($0) }

        let pending = QuestionGate.pendingQuestions(for: components)
        if !pending.isEmpty { emit(.questionsNeeded(pending)) }

        return ScanResult(title: response.sceneTitle ?? components.first?.name ?? "Scan", mode: mode, photo: image,
                          components: components, totals: ScanTotals.sum(components))
    }

    /// Spec §11: retry identify once before failing.
    private func identifyWithRetry(image: Data, hints: OCRHints) async throws -> IdentifyResponse {
        do {
            return try await services.vision.identify(image: image, hints: hints, profile: profile)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await services.vision.identify(image: image, hints: hints, profile: profile)
        }
    }

    private func resolveAll(_ components: [Component], ladder: EvidenceLadder,
                            emit: @escaping @Sendable (PipelineEvent) -> Void) async -> [Component] {
        let profile = profile
        return await withTaskGroup(of: (Int, Component).self) { group in
            for (index, component) in components.enumerated() {
                group.addTask {
                    let resolved = await ladder.resolve(component, profile: profile) { progress in
                        switch progress {
                        case let .resolved(metric, tier):
                            emit(.metricResolved(componentID: component.id, metric: metric, tier: tier))
                        case let .resolverFailed(name, error):
                            emit(.warning("\(name) unavailable for \(component.name): \(error.localizedDescription)"))
                        }
                    }
                    return (index, resolved)
                }
            }
            var output = components
            for await (index, resolved) in group { output[index] = resolved }
            return output
        }
    }

    private func makeComponent(_ identified: IdentifiedComponent) -> Component {
        var component = identified.makeComponent()
        if let load = identified.deferrableLoad {
            let watts = identified.quantities.ratedPowerW ?? identified.estimates[.powerOn]?.value ?? 100
            let yearly = identified.estimates[.yearlyElectricity]?.value
            let hours = identified.defaultUsage?.hoursOnPerDay ?? 2
            let daily = yearly.map { $0 / 365 } ?? watts * hours / 1000
            component.plugCandidate = PlugCandidate(loadType: load, chargerWatts: watts, dailyKWh: daily)
        }
        return component
    }
}
