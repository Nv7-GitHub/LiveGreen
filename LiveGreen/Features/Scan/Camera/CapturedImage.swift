import UIKit

/// Normalizes captured or imported images for the pipeline: orientation baked in, long edge capped at
/// 1568 px (the identify call's limit, spec §5.3), JPEG encoded.
nonisolated enum CapturedImage {
    static let maxLongEdge: CGFloat = 1568

    static func normalizedJPEG(from data: Data, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return normalizedJPEG(from: image, quality: quality)
    }

    static func normalizedJPEG(from image: UIImage, quality: CGFloat = 0.85) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxLongEdge / longEdge)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
