import Foundation
import ImageIO

/// What the device can tell about whether a picked image is a screenshot (C3), before identify sees it.
public enum ScreenshotSignal: String, Codable, Sendable, Hashable {
    /// The photo library or the file itself says so: the screenshot subtype, or the "Screenshot" description iOS
    /// writes into a screenshot's EXIF, TIFF and IPTC fields (kept when the photo is exported).
    case confirmed
    /// Only hinted: no camera data at all, and a phone-screen shape or a PNG file. Identify decides.
    case likely
}

/// Reads the screenshot signal from an image file's metadata. It must run on the picked file's own bytes:
/// normalizing for identify (`CapturedImage`) re-encodes the image and drops the metadata.
public enum ScreenshotDetection {
    /// Long-to-short edge ratios of phone screens (19.5:9 is 2.17, 16:9 is 1.78); camera photos are 4:3 or 3:2.
    static let screenAspects: ClosedRange<Double> = 1.75...2.3

    public static func signal(in data: Data) -> ScreenshotSignal? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        let descriptions = [exif[kCGImagePropertyExifUserComment], tiff[kCGImagePropertyTIFFImageDescription],
                            iptc[kCGImagePropertyIPTCCaptionAbstract]].compactMap { $0 as? String }
        if descriptions.contains(where: { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Screenshot") == .orderedSame }) {
            return .confirmed
        }
        let camera = tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil
            || exif[kCGImagePropertyExifLensModel] != nil || exif[kCGImagePropertyExifFNumber] != nil
            || exif[kCGImagePropertyExifExposureTime] != nil
        guard !camera else { return nil }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let aspect = min(width, height) > 0 ? max(width, height) / min(width, height) : 0
        let isPNG = (CGImageSourceGetType(source) as String?) == "public.png"
        return screenAspects.contains(aspect) || isPNG ? .likely : nil
    }
}
