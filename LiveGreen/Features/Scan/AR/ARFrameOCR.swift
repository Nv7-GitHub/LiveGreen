import CoreGraphics
import Vision
import GreenCore

/// On-device Vision pre-pass for an AR capture: barcodes plus accurate text recognition → `OCRHints`.
nonisolated enum ARFrameOCR {
    static func hints(for image: CGImage) async -> OCRHints {
        async let barcodes = barcodePayloads(in: image)
        async let lines = textLines(in: image)
        return await ARHintParser.hints(textLines: lines, barcodes: barcodes)
    }

    private static func barcodePayloads(in image: CGImage) async -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8, .upce, .itf14, .gs1DataBar, .code128, .qr]
        let observations = (try? await request.perform(on: image)) ?? []
        return observations.compactMap(\.payloadString)
    }

    /// Recognized lines, top to bottom (Vision's normalized origin is bottom-left).
    private static func textLines(in image: CGImage) async -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = (try? await request.perform(on: image)) ?? []
        return observations
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
