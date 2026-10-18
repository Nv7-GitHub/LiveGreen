import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The copy of a scan's photo kept in `ScanResult.photo`: saved with the scan, loaded with every scan in History,
/// shown on the results and sent to the greener-image edit. Identify gets the full photo (`IdentifyImage`, up to
/// 2576 px) for its small print; nothing that shows or edits the photo needs more than 1568 px.
public enum ScanPhoto {
    public static let maxLongEdge = 1568

    /// The photo scaled down to `maxLongEdge` on its long edge and JPEG encoded. A photo that already fits, or that
    /// cannot be read, is returned unchanged, so a photo is never lost and demo photos keep their bytes. The same input
    /// always gives the same bytes: the AR view finds the saved scan of its capture by comparing them.
    public static func stored(_ photo: Data, quality: Double = 0.85) -> Data {
        guard let source = CGImageSourceCreateWithData(photo as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > maxLongEdge else { return photo }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
        ]
        let output = NSMutableData()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return photo }
        let encoding = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, encoding)
        return CGImageDestinationFinalize(destination) ? output as Data : photo
    }
}
