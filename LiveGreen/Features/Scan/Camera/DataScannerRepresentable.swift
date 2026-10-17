import AVFoundation
import SwiftUI
import VisionKit

/// SwiftUI wrapper for VisionKit's live `DataScannerViewController`, recognizing barcodes and text.
/// Every barcode payload and text transcript seen is reported, so a label can be read by panning.
struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void
    var onText: (String) -> Void

    /// True when the device has the hardware and the user has granted camera access.
    static var isReady: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    /// Prompts for camera access the first time, then reports whether live scanning can run.
    static func requestAccessIfNeeded() async -> Bool {
        guard DataScannerViewController.isSupported else { return false }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return isReady
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerRepresentable

        init(parent: DataScannerRepresentable) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            addedItems.forEach(report)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            updatedItems.forEach(report)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report(item)
        }

        private func report(_ item: RecognizedItem) {
            switch item {
            case let .barcode(barcode):
                if let payload = barcode.payloadStringValue { parent.onBarcode(payload) }
            case let .text(text):
                parent.onText(text.transcript)
            @unknown default:
                break
            }
        }
    }
}
