import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Puts the greener edit on the original photo's exact frame, so the before/after halves line up (G3 of the image
/// QA). Grok returns its own size (1024×1024, or another aspect than the photo's), and showing each image fitted on
/// its own made tall screenshots jump at the divider. An edit can map onto the photo three ways: the whole photo
/// squeezed into the edit's frame, a centered crop of it, or the whole photo letterboxed inside it. Each is tried on
/// small grayscale copies and the one closest to the original wins, since an edit changes only a few objects.
public enum GreenerImageFit {
    /// How the edit's frame relates to the photo's.
    enum Mapping: CaseIterable {
        /// The whole photo, squeezed or stretched to the edit's aspect.
        case stretched
        /// A centered part of the photo at the edit's aspect; the rest of the photo is kept around it.
        case cropped
        /// The whole photo inside the edit, with bands at the sides or top and bottom.
        case padded
    }

    /// Side of the grayscale grid the mappings are compared on.
    static let probeSize = 48

    /// The edit redrawn at the original's pixel size, as JPEG; nil when either image cannot be read. Same-aspect
    /// edits are only scaled.
    public static func fitted(_ edited: Data, to original: Data) -> Data? {
        guard let before = image(original), let after = image(edited) else { return nil }
        let mapping = bestMapping(before: before, after: after)
        guard let frame = render(after, onto: before, mapping: mapping) else { return nil }
        return jpeg(frame)
    }

    static func bestMapping(before: CGImage, after: CGImage) -> Mapping {
        guard abs(aspect(before) / aspect(after) - 1) > 0.01 else { return .stretched }
        return Mapping.allCases.min { difference(before, after, $0) < difference(before, after, $1) } ?? .stretched
    }

    /// Mean gray-level difference between the part of the photo the edit covers and the edit's matching part.
    static func difference(_ before: CGImage, _ after: CGImage, _ mapping: Mapping) -> Double {
        let (photoPart, editPart) = parts(before, after, mapping)
        guard let a = gray(before, cropping: photoPart), let b = gray(after, cropping: editPart) else { return .infinity }
        return zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
    }

    /// The matching rectangles in each image's pixels: the photo's part the edit shows, and the edit's part that
    /// shows it.
    static func parts(_ before: CGImage, _ after: CGImage, _ mapping: Mapping) -> (photo: CGRect, edit: CGRect) {
        let photo = CGRect(x: 0, y: 0, width: before.width, height: before.height)
        let edit = CGRect(x: 0, y: 0, width: after.width, height: after.height)
        switch mapping {
        case .stretched: return (photo, edit)
        case .cropped: return (centered(aspect(after), in: photo), edit)
        case .padded: return (photo, centered(aspect(before), in: edit))
        }
    }

    /// The largest rectangle of `aspect` centered in `rect`.
    static func centered(_ aspect: Double, in rect: CGRect) -> CGRect {
        if rect.width / rect.height > aspect {
            let width = (rect.height * aspect).rounded()
            return CGRect(x: ((rect.width - width) / 2).rounded(), y: 0, width: width, height: rect.height)
        }
        let height = (rect.width / aspect).rounded()
        return CGRect(x: 0, y: ((rect.height - height) / 2).rounded(), width: rect.width, height: height)
    }

    /// The edit on the photo's frame: the photo first (it shows only where a cropped edit does not reach), then the
    /// edit's matching part over the photo's.
    static func render(_ after: CGImage, onto before: CGImage, mapping: Mapping) -> CGImage? {
        let (photoPart, editPart) = parts(before, after, mapping)
        guard let piece = after.cropping(to: editPart),
              let context = CGContext(data: nil, width: before.width, height: before.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let frame = CGRect(x: 0, y: 0, width: before.width, height: before.height)
        context.draw(before, in: frame)
        // Core Graphics counts y from the bottom; the parts are centered, so only the vertical offset flips.
        context.draw(piece, in: CGRect(x: photoPart.minX, y: frame.height - photoPart.maxY,
                                       width: photoPart.width, height: photoPart.height))
        return context.makeImage()
    }

    /// The image's part scaled to the probe grid as 8-bit gray.
    static func gray(_ image: CGImage, cropping part: CGRect) -> [UInt8]? {
        guard let piece = image.cropping(to: part) else { return nil }
        var pixels = [UInt8](repeating: 0, count: probeSize * probeSize)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: probeSize, height: probeSize,
                                          bitsPerComponent: 8, bytesPerRow: probeSize,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(piece, in: CGRect(x: 0, y: 0, width: probeSize, height: probeSize))
            return true
        }
        return drawn ? pixels : nil
    }

    static func aspect(_ image: CGImage) -> Double {
        Double(image.width) / Double(max(image.height, 1))
    }

    /// Decodes with the orientation applied, so the pixels are the way the photo is shown.
    static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.9) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
