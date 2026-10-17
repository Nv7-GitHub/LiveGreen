import SwiftUI
import PhotosUI
import GreenCore

/// Photo capture mode (spec §5.1): pick or take a still, then hand JPEG data and OCR hints to the pipeline.
struct PhotoScanView: View {
    let onCapture: (Data, OCRHints) -> Void
    @State private var selection: PhotosPickerItem?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.moss, .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder").font(.system(size: 64)).foregroundStyle(.white.opacity(0.8))
                PhotosPicker(selection: $selection, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.glassProminent)
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    onCapture(data, .none)
                }
                selection = nil
            }
        }
    }
}

#Preview {
    PhotoScanView { _, _ in }
}
