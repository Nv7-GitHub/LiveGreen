import Foundation
import ImageIO
import Vision
import GreenCore

/// On-device pre-pass (spec §5.2): barcode detection plus accurate text recognition on a captured
/// frame, parsed into `OCRHints` for the identify call.
nonisolated enum VisionOCR {
    /// Runs both Vision requests off the main actor. Returns `.none` when the image cannot be decoded.
    static func hints(for imageData: Data) async -> OCRHints {
        await Task.detached(priority: .userInitiated) {
            analyze(imageData)
        }.value
    }

    /// Synchronous variant; call from a background context.
    static func analyze(_ imageData: Data) -> OCRHints {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .none }
        let observations = recognize(image, orientation: orientation(of: source))
        return OCRTextParser.hints(barcodePayloads: observations.payloads, textLines: observations.lines)
    }

    static let retailSymbologies: [VNBarcodeSymbology] = [.ean8, .ean13, .upce, .itf14, .gs1DataBar, .code128, .qr]

    private static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) -> (payloads: [String], lines: [String]) {
        let barcodes = VNDetectBarcodesRequest()
        barcodes.symbologies = retailSymbologies

        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        // Model numbers and GTINs are not dictionary words; correction would "fix" them.
        text.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        do {
            try handler.perform([barcodes, text])
        } catch {
            return ([], [])
        }

        let payloads = (barcodes.results ?? []).compactMap(\.payloadStringValue)
        // Vision boxes have a bottom-left origin: sort by descending top edge for reading order.
        let lines = (text.results ?? [])
            .sorted { lhs, rhs in
                abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.01
                    ? lhs.boundingBox.maxY > rhs.boundingBox.maxY
                    : lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
        return (payloads, lines)
    }

    private static func orientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = properties?[kCGImagePropertyOrientation] as? UInt32
        return raw.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
    }
}
