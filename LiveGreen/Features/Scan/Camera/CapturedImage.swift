import GreenCore
import UIKit

/// Normalizes captured or imported images for the pipeline: orientation baked in, scaled down to the identify
/// call's image limits (`IdentifyImage`: 2576 px long edge, ~3.7 MP, spec §5.3) so keyboard legends, logos and
/// small print stay readable for the model and the on-device OCR, JPEG encoded.
nonisolated enum CapturedImage {
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
