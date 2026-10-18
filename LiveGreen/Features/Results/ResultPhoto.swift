import SwiftUI
import UIKit
import GreenCore

/// The captured still at its own aspect ratio, so normalized boxes map onto it directly, with `overlay` (the
/// hotspots) drawn on the image itself. With `maxHeight`, a tall photo is shown at most that tall, centered on a
/// blurred copy of itself, so a phone screenshot no longer fills the first screen. Personal text read in the photo
/// (a name and address sticker) is blurred once on-device OCR has run (`PhotoRedaction`). Barcode scans show the
/// product's pack shot from its record; scans without any photo get a neutral 4:3 backdrop.
struct ResultPhoto<Overlay: View>: View {
    let data: Data?
    var mode: ScanMode = .photo
    var maxHeight: CGFloat?
    @ViewBuilder var overlay: Overlay

    /// The redaction outcome and the photo it was made for.
    @State private var redaction: (data: Data, outcome: PhotoRedaction.Outcome)?

    private var image: UIImage? { data.flatMap(UIImage.init(data:)) }

    /// The redacted copy when there is one for this photo (from this view or the session cache), else the photo.
    private func shown(_ image: UIImage) -> UIImage {
        guard let data else { return image }
        let outcome = redaction.flatMap { $0.data == data ? $0.outcome : nil } ?? PhotoRedaction.cached(data)
        if case .image(let redacted) = outcome { return redacted }
        return image
    }

    var body: some View {
        if let image {
            if mode == .barcode {
                // Pack shots are small and often tall; center them on a light card instead of stretching.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(.white)
                    .accessibilityLabel("Product photo")
                    .overlay { overlay }
            } else {
                photo(image)
            }
        } else {
            LinearGradient(colors: [Theme.moss.opacity(0.8), Theme.leaf.opacity(0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .aspectRatio(mode == .barcode ? 2 : 4 / 3, contentMode: .fit)
                .overlay {
                    if mode == .barcode {
                        Image(systemName: "barcode")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Label("No photo", systemImage: "photo")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(10)
                }
                .overlay { overlay }
        }
    }

    private func photo(_ original: UIImage) -> some View {
        let image = shown(original)
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 4 / 3
        return Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel("Scanned photo")
            // On the image itself: on the container it would replace every hotspot's identifier.
            .accessibilityIdentifier("resultPhoto")
            .overlay { overlay }
            // Capping the width caps the height: a fitted image is its width over its aspect ratio tall.
            .frame(maxWidth: maxHeight.map { $0 * aspect } ?? .infinity)
            .frame(maxWidth: .infinity)
            // Fills the bands beside a capped photo, so the card keeps its full width and rounded corners.
            .background {
                if maxHeight != nil {
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: 24, opaque: true)
                        }
                        .overlay(.black.opacity(0.12))
                        .clipped()
                        .accessibilityHidden(true)
                }
            }
            .task(id: data) {
                guard let data else { return }
                redaction = (data, await PhotoRedaction.outcome(for: data))
            }
    }
}
