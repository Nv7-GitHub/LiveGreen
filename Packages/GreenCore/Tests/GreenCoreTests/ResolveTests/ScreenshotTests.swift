import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GreenCore
import GreenCoreFakes

/// Screenshots (C3): detected from the picked file, framed as seen on screen rather than the user's own footprint,
/// and cropped to the post's or listing's own picture.
@Suite("Screenshots")
struct ScreenshotTests {
    private struct FixedVision: VisionIdentifier {
        var response: IdentifyResponse
        func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse { response }
    }

    private func pipeline(_ response: IdentifyResponse) -> ScanPipeline {
        let store = ReferenceStore.bundled
        return ScanPipeline(vision: FixedVision(response: response), alternatives: FakeAlternativeSuggester(),
                            products: FakeProductDatabase(),
                            ladder: EvidenceLadder(resolvers: [FactorModelResolver(store: store), EstimateResolver()]),
                            engine: ImpactEngine(reference: store), profile: .default)
    }

    /// A plain image file with the given metadata.
    private func image(width: Int, height: Int, properties: [CFString: Any] = [:], type: UTType = .jpeg) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let picture = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, picture, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func size(of data: Data?) throws -> (Int, Int) {
        let source = try #require(data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) })
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private let post = IdentifyResponse(components: [
        IdentifiedComponent(name: "Tofu salad", category: .food, boundingBox: NormalizedRect(x: 0.1, y: 0.3, width: 0.5, height: 0.6),
                            quantities: Quantities(massKg: 0.3, servingKg: 0.3, foodGroup: "tofu"),
                            estimates: [.carbon: EstimateRange(value: 0.5, low: 0.3, high: 0.9)],
                            anchor: NormalizedPoint(x: 0.3, y: 0.4)),
    ], sceneTitle: "Salad post", sceneContext: .own, photoRegion: NormalizedRect(x: 0, y: 0.2, width: 1, height: 0.5))

    // MARK: Detection

    @Test func readsTheScreenshotMarkFromTheFile() throws {
        // What iOS writes into a screenshot, kept when it is exported (15, 17, 27).
        let marked = try image(width: 601, height: 1306, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Screenshot"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: "Screenshot"],
        ])
        #expect(ScreenshotDetection.signal(in: marked) == .confirmed)
        // No camera data and a phone-screen shape, or a PNG: only a hint.
        #expect(ScreenshotDetection.signal(in: try image(width: 1179, height: 2556)) == .likely)
        #expect(ScreenshotDetection.signal(in: try image(width: 400, height: 300, type: .png)) == .likely)
        // A camera photo, even a tall one, is not.
        let camera = try image(width: 1179, height: 2556, properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 17 Pro"],
        ])
        #expect(ScreenshotDetection.signal(in: camera) == nil)
        #expect(ScreenshotDetection.signal(in: try image(width: 1024, height: 768)) == nil)
        #expect(ScreenshotDetection.signal(in: Data([1, 2, 3])) == nil)
    }

    @Test func identifyHearsWhatTheDeviceFound() {
        let confirmed = ClaudeClient.identifyUserText(hints: OCRHints(screenshot: .confirmed), profile: .default)
        #expect(confirmed.contains("marks this image as a screenshot"))
        #expect(ClaudeClient.identifyUserText(hints: OCRHints(screenshot: .likely), profile: .default)
            .contains("it may be a screenshot"))
        #expect(!ClaudeClient.identifyUserText(hints: .none, profile: .default).contains("Capture:"))
        let system = ClaudeClient.identifySystemPrompt(vocabulary: .default, carbonEstimateOnly: true)
        #expect(system.contains("give photo_region"))
    }

    @Test func parsesThePhotoRegion() throws {
        let input: JSONValue = ["scene_title": "Post", "scene_context": "screenshot", "components": [],
                                "photo_region": ["x": 0, "y": 0.18, "width": 1, "height": 0.61]]
        let response = try ReportComponentsTool.parse(input)
        #expect(response.sceneContext == .screenshot)
        #expect(response.photoRegion == NormalizedRect(x: 0, y: 0.18, width: 1, height: 0.61))
        let malformed: JSONValue = ["scene_title": "Post", "scene_context": "screenshot", "components": [], "photo_region": "top"]
        #expect(try ReportComponentsTool.parse(malformed).photoRegion == nil)
        let schema = ReportComponentsTool.carbonEstimateOnlySchema
        #expect(schema["properties"]?["photo_region"]?["required"] == ["x", "y", "width", "height"])
        #expect(schema["required"]?.array?.compactMap(\.string).contains("photo_region") == false)
    }

    // MARK: Pipeline

    @Test func aMarkedScreenshotIsSeenOnScreenAndCropped() async throws {
        let photo = try image(width: 600, height: 1300)
        let result = try await pipeline(post).run(image: photo, hints: OCRHints(screenshot: .confirmed), mode: .photo)
        // The device's mark wins over identify's "own".
        #expect(result.sceneContext == .screenshot)
        #expect(result.isScreenshot)
        let salad = try #require(result.components.first)
        #expect(salad.exclusion == .onScreen)
        #expect(!salad.isCounted, "a stranger's post never reaches the footprint")
        #expect(result.totaledComponents.count == 1, "shown as what it would add if bought")
        #expect(result.yearlyTotals[.carbon] != nil)
        #expect(ScannedFootprint.from(scans: [result]).yearly[.carbon] == nil)

        // Cropped to the post's photo, with the box and anchor moved into it.
        let (width, height) = try size(of: result.photo)
        #expect(width == 600 && height == 650)
        #expect(abs(salad.boundingBox.y - 0.2) < 1e-9 && abs(salad.boundingBox.height - 0.8) < 1e-9)
        #expect(abs((salad.anchor?.y ?? 0) - 0.4) < 1e-9)

        // "I bought it" counts it.
        var bought = result
        bought.markOwned(true, componentID: salad.id, engine: ImpactEngine())
        #expect(ScannedFootprint.from(scans: [bought]).yearly[.carbon] != nil)
    }

    @Test func aCameraPhotoOfAScreenKeepsItsFrame() async throws {
        let photo = try image(width: 600, height: 800)
        var screen = post
        screen.sceneContext = .screenshot
        let result = try await pipeline(screen).run(image: photo, hints: .none, mode: .photo)
        #expect(result.sceneContext == .screenshot, "identify's call stands")
        let (width, height) = try size(of: result.photo)
        #expect(width == 600 && height == 800, "no device mark: not cropped, so the Integrated view still finds its scan")
        #expect(result.components.first?.boundingBox == post.components[0].boundingBox)
    }

    @Test func regionsThatCutNothingOrAlmostEverythingAreIgnored() throws {
        let photo = try image(width: 100, height: 200)
        let hints = OCRHints(screenshot: .likely)
        let items = post.components
        for region in [NormalizedRect.full, NormalizedRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)] {
            let kept = ScanPipeline.croppedToPhoto(items, image: photo, region: region, scene: .screenshot, hints: hints)
            #expect(kept.image == photo)
            #expect(kept.components == items)
        }
        let own = ScanPipeline.croppedToPhoto(items, image: photo, region: post.photoRegion, scene: .own, hints: hints)
        #expect(own.image == photo, "only screenshots are cropped")
    }
}
