import Foundation

extension ScanPipeline {
    /// The scan's scene: a screenshot when the photo library or the file's metadata says so, whatever identify
    /// answered; else identify's `scene_context`; nil (the user's own) when it gave none, as for barcode scans.
    static func sceneContext(of response: IdentifyResponse, hints: OCRHints) -> SceneContext? {
        hints.screenshot == .confirmed ? .screenshot : response.sceneContext
    }

    /// A region to crop to must leave out something worth leaving out (the app's bars and captions) and still be a
    /// real part of the photo.
    static let croppableArea: ClosedRange<Double> = 0.05...0.9

    /// A screenshot's photo cropped to identify's `photo_region`, so the results and the greener image show the post's
    /// or listing's own picture without the app's status bar, tab bar, usernames and comments, with the items' boxes and
    /// anchors moved into it. Only a picked image the device also took for a screenshot is cropped: a camera photo of
    /// a screen keeps its frame (the Integrated view finds its saved scan by the photo's bytes). Unchanged otherwise,
    /// without a usable region, or when the crop fails.
    static func croppedToPhoto(_ components: [IdentifiedComponent], image: Data, region: NormalizedRect?,
                               scene: SceneContext?, hints: OCRHints) -> (components: [IdentifiedComponent], image: Data) {
        guard scene == .screenshot, hints.screenshot != nil, !image.isEmpty, let region = region?.clamped,
              croppableArea.contains(region.area), min(region.width, region.height) >= 0.2,
              let cropped = ScanPhoto.cropped(image, to: region) else { return (components, image) }
        let moved = components.map { component in
            var copy = component
            copy.boundingBox = component.boundingBox.relative(to: region)
            copy.anchor = component.anchor?.relative(to: region)
            return copy
        }
        return (moved, cropped)
    }
}
