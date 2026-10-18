import GreenCore
import Photos
import UIKit

/// Normalizes captured or imported images for the pipeline: orientation baked in, scaled down to the identify
/// call's image limits (`IdentifyImage`: 2576 px long edge, ~3.7 MP, spec §5.3) so keyboard legends, logos and
/// small print stay readable for the model and the on-device OCR, JPEG encoded. The re-encoding drops the file's
/// metadata, so read anything needed from it first (`screenshotSignal`).
nonisolated enum CapturedImage {
    /// Whether a picked image is a screenshot (C3): the photo library's screenshot subtype when the app may read the
    /// asset (it never asks for that permission), else the file's own metadata (`ScreenshotDetection`).
    static func screenshotSignal(in data: Data, assetIdentifier: String?) -> ScreenshotSignal? {
        if let assetIdentifier, [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite)),
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject,
           asset.mediaSubtypes.contains(.photoScreenshot) {
            return .confirmed
        }
        return ScreenshotDetection.signal(in: data)
    }

    static func normalizedJPEG(from data: Data, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return normalizedJPEG(from: image, quality: quality)
    }

    static func normalizedJPEG(from image: UIImage, quality: CGFloat = 0.85) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let fitted = IdentifyImage.fittedSize(width: size.width, height: size.height)
        let target = CGSize(width: fitted.width, height: fitted.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
