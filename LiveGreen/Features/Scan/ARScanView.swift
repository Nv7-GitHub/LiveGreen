import SwiftUI
import GreenCore

/// AR capture mode (spec §5.1): world-tracked camera, capture a frame, anchor glass labels per component.
struct ARScanView: View {
    let onCapture: (Data, OCRHints) -> Void
    /// Result whose components should be anchored as labels, once available.
    var result: ScanResult?
    var onSelectComponent: (Component) -> Void = { _ in }

    var body: some View {
        ZStack {
            Color.black
            ContentUnavailableView("AR scan", systemImage: "arkit",
                                   description: Text("Point at a scene and capture to anchor labels on each item."))
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ARScanView { _, _ in }
}
