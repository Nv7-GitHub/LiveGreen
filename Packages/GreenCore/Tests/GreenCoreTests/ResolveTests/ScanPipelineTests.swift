import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenCore
import GreenCoreFakes

@Suite("Scan pipeline")
struct ScanPipelineTests {
    private func pipeline(scene: DemoScene = .deskSetup, vision: (any VisionIdentifier)? = nil,
                          cache: (any ResolutionCache)? = nil,
                          products: any ProductDatabase = FakeProductDatabase()) -> ScanPipeline {
        let store = ReferenceStore.bundled
        let resolvers: [any MetricResolver] = [
            OpenFoodFactsResolver(products: products), EnergyStarResolver(appliances: FakeApplianceDatabase()),
            ASUSPCFResolver(store: store), SpecResearchResolver(researcher: FakeSpecResearcher()),
            FactorModelResolver(store: store), EstimateResolver(),
        ]
        return ScanPipeline(vision: vision ?? FakeVisionIdentifier(scene: scene), alternatives: FakeAlternativeSuggester(),
                            products: products, ladder: EvidenceLadder(resolvers: resolvers, cache: cache),
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

    /// A name-only record like most US drinks on Open Food Facts: no size, packaging or footprint data.
    private static let seltzer = ProductRecord(
        gtin: "0071537003673", name: "Polar Seltzer", brand: "Polar", category: .food,
        sourceURL: URL(string: "https://world.openfoodfacts.org/product/0071537003673")!,
        foodGroup: "bottled_water", imageURL: URL(string: "https://images.openfoodfacts.org/front.jpg")!)

    @Test func nameOnlyBarcodeRecordIsIdentifiedByName() async throws {
        let vision = RecordingVision()
        let products = PhotoProductDatabase(records: [Self.seltzer.gtin: Self.seltzer], photo: Data([7, 7]))
        let result = try await pipeline(vision: vision, products: products)
            .run(image: Data(), hints: OCRHints(gtins: [Self.seltzer.gtin]), mode: .barcode)
        #expect(vision.hints.first?.textLines.first?.contains("Polar Seltzer") == true)
        #expect(result.photo == Data([7, 7]))
        #expect(result.components.count == 1)
    }

    @Test func nameOnlyRecordFallbackStillGetsWaterAndNoFalsePlasticZero() async throws {
        let failing = FailingVision()
        let products = PhotoProductDatabase(records: [Self.seltzer.gtin: Self.seltzer], photo: nil)
        let result = try await pipeline(vision: failing, products: products)
            .run(image: Data(), hints: OCRHints(gtins: [Self.seltzer.gtin]), mode: .barcode)
        #expect(failing.attempts == 2)
        let seltzer = try #require(result.components.first)
        #expect((seltzer.metrics[.water]?.value ?? 0) > 0)
        #expect(seltzer.metrics[.carbon] != nil)
        #expect(seltzer.metrics[.plasticMass] == nil)
        #expect(result.photo == nil)
    }

    @Test func alternativesGoThroughTheLadderAndAddThePlugOption() async throws {
        let pipeline = pipeline(scene: .eBikeCorner)
        let result = try await pipeline.run(image: Data([1]), hints: .none, mode: .photo)
        let updated = try await pipeline.suggestAlternatives(for: result)
        let bike = try #require(updated.components.first { $0.name == "E-bike" })
        #expect(bike.alternatives.contains { $0.kind == .smartPlugScheduling })
        let product = try #require(bike.alternatives.first { $0.kind == .product })
        // Unidentified swaps use the suggester's own estimates rather than the original's generic factors.
        let carbon = try #require(product.metrics[.carbon])
        #expect(carbon.value < bike.metrics[.carbon]!.value)
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

    private struct PhotoRecordingVision: VisionIdentifier {
        let images = Recorder<Data>()
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
            images.append(image)
            return DemoScene.deskSetup.identifyResponse
        }
    }

    @Test func identifyGetsTheFullPhotoAndTheResultKeepsASmallerCopy() async throws {
        let photo = try Self.jpeg(width: 2576, height: 1932)
        let vision = PhotoRecordingVision()
        let result = try await pipeline(vision: vision).run(image: photo, hints: .none, mode: .photo)
        #expect(vision.images.values == [photo])
        let stored = try #require(result.photo)
        let size = try #require(Self.pixelSize(stored))
        #expect(size.width == ScanPhoto.maxLongEdge && abs(size.height - 1176) <= 1)
        #expect(stored.count < photo.count)
        // The copy is the same every time: the AR view finds the saved scan of its capture by comparing it.
        #expect(ScanPhoto.stored(photo) == stored)
        // A photo that already fits keeps its bytes (demo scenes are matched by them), as does unreadable data.
        let small = try Self.jpeg(width: 1200, height: 900)
        #expect(ScanPhoto.stored(small) == small)
        #expect(ScanPhoto.stored(Data([1])) == Data([1]))
    }

    /// A JPEG with some detail in it, as the camera would hand over.
    static func jpeg(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for row in 0..<12 {
            for column in 0..<16 {
                context.setFillColor(red: Double(row) / 12, green: Double(column) / 16, blue: 0.5, alpha: 1)
                context.fill(CGRect(x: column * width / 16, y: row * height / 12, width: width / 16, height: height / 12))
            }
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func pixelSize(_ jpeg: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
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

final class RecordingVision: VisionIdentifier, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [OCRHints] = []
    var hints: [OCRHints] { lock.withLock { received } }

    func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        lock.withLock { received.append(hints) }
        let gtin = hints.gtins.first
        return IdentifyResponse(components: [IdentifiedComponent(
            name: "Polar Seltzer, 12 fl oz can", category: .food, boundingBox: .full,
            identifiers: Identifiers(gtin: gtin, brand: "Polar", materials: [MaterialShare(material: "aluminium", percent: 100)]),
            quantities: Quantities(packagingMassG: 13, volumeLiters: 0.355, foodGroup: "bottled_water"))])
    }
}

struct PhotoProductDatabase: ProductDatabase {
    var records: [String: ProductRecord]
    var photo: Data?

    func product(gtin: String) async throws -> ProductRecord? { records[gtin] }
    func productImage(for record: ProductRecord) async -> Data? { photo }
}
