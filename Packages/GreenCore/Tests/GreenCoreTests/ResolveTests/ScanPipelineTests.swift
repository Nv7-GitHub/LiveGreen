import Foundation
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Scan pipeline")
struct ScanPipelineTests {
    private func pipeline(scene: DemoScene = .deskSetup, vision: (any VisionIdentifier)? = nil,
                          cache: (any ResolutionCache)? = nil) -> ScanPipeline {
        let store = ReferenceStore.bundled
        let resolvers: [any MetricResolver] = [
            OpenFoodFactsResolver(products: FakeProductDatabase()), EnergyStarResolver(appliances: FakeApplianceDatabase()),
            ASUSPCFResolver(store: store), SpecResearchResolver(researcher: FakeSpecResearcher()),
            FactorModelResolver(store: store), EstimateResolver(),
        ]
        return ScanPipeline(vision: vision ?? FakeVisionIdentifier(scene: scene), alternatives: FakeAlternativeSuggester(),
                            products: FakeProductDatabase(), ladder: EvidenceLadder(resolvers: resolvers, cache: cache),
                            engine: ImpactEngine(reference: store), profile: .default)
    }

    @Test func everySceneResolvesWithMixedTiers() async throws {
        for scene in DemoScene.allCases {
            let result = try await pipeline(scene: scene).run(image: Data([1]), hints: .none, mode: .photo)
            #expect(!result.components.isEmpty)
            for component in result.components {
                #expect(component.missingMetrics.isEmpty, "\(scene) \(component.name) missing \(component.missingMetrics)")
            }
            #expect(result.totals[.carbon] != nil)
        }
        let desk = try await pipeline().run(image: Data([1]), hints: .none, mode: .photo)
        let tiers = Set(desk.components.flatMap { $0.metrics.values.map(\.tier) })
        #expect(tiers.contains(.exactRecord))
        #expect(tiers.contains(.researchedSpec))
        #expect(tiers.contains(.factorModel))
    }

    @Test func emitsStepsInOrder() async throws {
        let log = EventLog()
        _ = try await pipeline().run(image: Data([1]), hints: .none, mode: .photo) { log.append($0) }
        let started = log.events.compactMap { event -> PipelineStep? in
            if case let .stepStarted(step) = event { step } else { nil }
        }
        #expect(started == PipelineStep.allCases)
        #expect(log.events.contains { if case .componentsIdentified = $0 { true } else { false } })
        #expect(log.events.contains { if case .questionsNeeded = $0 { true } else { false } })
    }

    @Test func sameScanIDGivesIdenticalResults() async throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try await pipeline().run(id: id, date: date, image: Data([1]), hints: .none, mode: .photo)
        let b = try await pipeline().run(id: id, date: date, image: Data([1]), hints: .none, mode: .photo)
        #expect(a.totals == b.totals)
        #expect(a.components.map(\.metrics) == b.components.map(\.metrics))
    }

    @Test func rescanningAnIdentifierReusesCachedNumbers() async throws {
        let cache = InMemoryResolutionCache()
        let first = try await pipeline(cache: cache).run(image: Data([1]), hints: .none, mode: .photo)
        let second = try await pipeline(cache: cache).run(image: Data([1]), hints: .none, mode: .photo)
        let firstMonitor = try #require(first.components.first { $0.identifiers.model == "S2721H" })
        let secondMonitor = try #require(second.components.first { $0.identifiers.model == "S2721H" })
        #expect(firstMonitor.metrics == secondMonitor.metrics)
    }

    @Test func deferrableLoadsGetAPlugCandidateWithSavings() async throws {
        let result = try await pipeline(scene: .eBikeCorner).run(image: Data([1]), hints: .none, mode: .photo)
        let bike = try #require(result.components.first { $0.name == "E-bike" })
        let candidate = try #require(bike.plugCandidate)
        #expect(candidate.loadType == .eBike)
        #expect(candidate.dailyKWh > 0)
        #expect((candidate.estimatedSavings?.value ?? 0) > 0)
    }

    @Test func barcodeRecordsStandInWhenIdentifyFails() async throws {
        let failing = FailingVision()
        let hints = OCRHints(gtins: ["5449000000996"])
        let result = try await pipeline(vision: failing).run(image: Data([1]), hints: hints, mode: .barcode)
        #expect(result.components.map(\.identifiers.gtin) == ["5449000000996"])
        #expect(result.components[0].metrics[.carbon]?.tier == .exactRecord)
        #expect(failing.attempts == 2)

        await #expect(throws: GreenCoreError.self) {
            try await pipeline(vision: FailingVision()).run(image: Data([1]), hints: .none, mode: .photo)
        }
    }

    @Test func barcodeOnlyScanSkipsIdentify() async throws {
        let failing = FailingVision()
        let result = try await pipeline(vision: failing).run(image: Data(), hints: OCRHints(gtins: ["5449000000996"]),
                                                             mode: .barcode)
        #expect(result.components.count == 1)
        #expect(failing.attempts == 0)
        #expect(result.photo == nil)
    }

    @Test func alternativesGoThroughTheLadderAndAddThePlugOption() async throws {
        let pipeline = pipeline(scene: .eBikeCorner)
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let updated = try await pipeline.suggestAlternatives(for: result)
        let bike = try #require(updated.components.first { $0.name == "E-bike" })
        #expect(bike.alternatives.contains { $0.kind == .smartPlugScheduling })
        let product = try #require(bike.alternatives.first { $0.kind == .product })
        #expect(product.metrics[.carbon] != nil)
    }

    @Test func answersRerunTheEngineLocally() async throws {
        let pipeline = pipeline()
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let monitor = try #require(result.components.first { $0.identifiers.model == "S2721H" })
        let option = AnswerOption(label: "~2 h", field: .hoursOnPerDay, value: 2)
        let updated = pipeline.applying([(monitor.id, option)], to: result)
        let after = try #require(updated.component(withID: monitor.id))
        #expect(after.usage?.hoursOnPerDay == 2)
        #expect(try #require(after.metrics[.yearlyElectricity]).value < monitor.metrics[.yearlyElectricity]!.value)
        #expect(try #require(updated.totals[.carbon]).value < result.totals[.carbon]!.value)
    }
}

final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [PipelineEvent] = []
    var events: [PipelineEvent] { lock.withLock { stored } }
    func append(_ event: PipelineEvent) { lock.withLock { stored.append(event) } }
}

final class FailingVision: VisionIdentifier, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var attempts: Int { lock.withLock { count } }

    func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        lock.withLock { count += 1 }
        throw GreenCoreError.timeout
    }
}
