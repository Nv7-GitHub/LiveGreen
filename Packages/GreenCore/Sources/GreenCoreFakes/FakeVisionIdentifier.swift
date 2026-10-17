import Foundation
import GreenCore

/// Returns a canned scene regardless of the image.
public struct FakeVisionIdentifier: VisionIdentifier {
    public var scene: DemoScene
    public var latency: Duration

    public init(scene: DemoScene = .deskSetup, latency: Duration = .zero) {
        self.scene = scene
        self.latency = latency
    }

    public func identify(image: Data, hints: OCRHints, profile: UserProfile) async throws -> IdentifyResponse {
        try await simulateLatency(latency)
        var response = scene.identifyResponse
        // A scanned barcode becomes its own component, as a barcode-only scan would.
        if let gtin = hints.gtins.first, !response.components.contains(where: { $0.identifiers.gtin == gtin }) {
            response.components.append(IdentifiedComponent(
                name: "Scanned product \(gtin)", category: .food, boundingBox: .full,
                identifiers: Identifiers(gtin: gtin),
                estimates: [.carbon: EstimateRange(value: 0.5, low: 0.2, high: 1.5)]))
        }
        return response
    }
}
