import CoreImage
import Foundation
import ImageIO
import UIKit
import Vision
import GreenCore

/// Blurs personal details in the results photo: names, addresses, phone numbers and emails that on-device OCR reads
/// (`PersonalText`), such as the owner sticker on a scanned notebook, so they are not legible to whoever is watching.
/// Display only: the stored scan keeps its photo. Outcomes are cached per photo for the session.
nonisolated enum PhotoRedaction {
    /// A blurred copy, or nothing to hide.
    enum Outcome: Sendable {
        case none
        case image(UIImage)
    }

    @MainActor private static var cache: [Data: Outcome] = [:]

    /// The cached outcome for a photo, so a scan opened again shows its redacted copy at once.
    @MainActor static func cached(_ data: Data) -> Outcome? { cache[data] }

    /// Runs OCR off the main actor the first time a photo is shown, then caches the outcome.
    @MainActor static func outcome(for data: Data) async -> Outcome {
        if let cached = cache[data] { return cached }
        let image = await Task.detached(priority: .userInitiated) { redact(data) }.value
        let outcome: Outcome = image.map { .image($0) } ?? .none
        // A handful of photos are open in one session; drop them all rather than track recency.
        if cache.count >= 12 { cache.removeAll() }
        cache[data] = outcome
        return outcome
    }

    /// The photo with personal text blurred, or nil when it has none or cannot be read. Synchronous; call it off the
    /// main actor.
    static func redact(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        // Upright, like the displayed `UIImage`, so boxes and pixels agree.
        let image = CIImage(cgImage: cgImage).oriented(orientation)
        let extent = image.extent

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Phone numbers and postcodes are not dictionary words; correction would "fix" them.
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(ciImage: image).perform([request])
        } catch {
            return nil
        }
        // Reading order (Vision boxes have a bottom-left origin), so a label and the line under it are neighbours.
        let observations = (request.results ?? []).sorted { lhs, rhs in
            abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.01
                ? lhs.boundingBox.maxY > rhs.boundingBox.maxY
                : lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        let sensitive = PersonalText.sensitiveLines(observations.map { $0.topCandidates(1).first?.string ?? "" })
        guard !sensitive.isEmpty else { return nil }

        // Core Image shares Vision's bottom-left origin, so normalized boxes map straight onto the extent.
        let rects = sensitive.map { index in
            let box = observations[index].boundingBox
            let rect = CGRect(x: extent.minX + box.minX * extent.width, y: extent.minY + box.minY * extent.height,
                              width: box.width * extent.width, height: box.height * extent.height)
            return rect.insetBy(dx: -rect.height * 0.4, dy: -rect.height * 0.35)
        }
        let lineHeight = rects.map(\.height).max() ?? 20
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: max(6, lineHeight * 0.5)).cropped(to: extent)
        let mask = rects.reduce(CIImage(color: .black).cropped(to: extent)) { mask, rect in
            CIImage(color: .white).cropped(to: rect).composited(over: mask)
        }
        let output = blurred.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image,
                                                                          kCIInputMaskImageKey: mask])
        guard let rendered = CIContext().createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
