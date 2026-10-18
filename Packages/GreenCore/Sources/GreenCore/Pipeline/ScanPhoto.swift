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

    /// The photo cropped to a normalized region, JPEG encoded; nil when it cannot be read, carries an orientation
    /// other than upright (identify photos have it baked in, so boxes map straight onto pixels) or the region is empty.
    public static func cropped(_ photo: Data, to region: NormalizedRect, quality: Double = 0.9) -> Data? {
        guard let source = CGImageSourceCreateWithData(photo as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let orientation = properties?[kCGImagePropertyOrientation] as? NSNumber, orientation.intValue != 1 { return nil }
        let width = Double(image.width), height = Double(image.height)
        let region = region.clamped
        let rect = CGRect(x: region.x * width, y: region.y * height, width: region.width * width,
                          height: region.height * height).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        guard rect.width >= 1, rect.height >= 1, let crop = image.cropping(to: rect),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, crop, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
