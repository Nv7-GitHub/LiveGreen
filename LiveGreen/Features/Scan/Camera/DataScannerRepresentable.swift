import AVFoundation
import SwiftUI
import VisionKit

/// A barcode currently in view, with its corners in the scanner view's coordinates.
struct TrackedBarcode: Identifiable, Equatable {
    let id: UUID
    var payload: String?
    /// Top-left, top-right, bottom-right, bottom-left.
    var corners: [CGPoint]
}

/// SwiftUI wrapper for VisionKit's live `DataScannerViewController`, recognizing barcodes and text.
/// Every barcode payload and text transcript seen is reported, so a label can be read by panning. VisionKit's
/// own highlighting boxes every text block too, so it is off; barcodes in view are reported through
/// `onTrackedBarcodes` for a custom overlay instead.
struct DataScannerRepresentable: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void
    var onText: (String) -> Void
    var onTrackedBarcodes: ([TrackedBarcode]) -> Void = { _ in }

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
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: false)
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
            track(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            updatedItems.forEach(report)
            track(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            track(allItems)
        }

        private func track(_ items: [RecognizedItem]) {
            let barcodes: [TrackedBarcode] = items.compactMap { item in
                guard case let .barcode(barcode) = item else { return nil }
                let b = barcode.bounds
                return TrackedBarcode(id: barcode.id, payload: barcode.payloadStringValue,
                                      corners: [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft])
            }
            parent.onTrackedBarcodes(barcodes)
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
