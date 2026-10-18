import Foundation

extension ScanPipeline {
    /// The scan's scene: identify's `scene_context`; nil (the user's own) when it gave none, as for barcode scans.
    static func sceneContext(of response: IdentifyResponse, hints: OCRHints) -> SceneContext? {
        response.sceneContext
    }
}
