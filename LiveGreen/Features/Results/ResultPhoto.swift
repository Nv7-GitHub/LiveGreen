import SwiftUI
import UIKit

/// The captured still at its own aspect ratio, so normalized boxes map onto it directly. Scans
/// without a photo (barcode lookups, demo replays) get a neutral 4:3 backdrop.
struct ResultPhoto: View {
    let data: Data?

    private var image: UIImage? { data.flatMap(UIImage.init(data:)) }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .accessibilityLabel("Scanned photo")
        } else {
            LinearGradient(colors: [Theme.moss.opacity(0.8), Theme.leaf.opacity(0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Label("No photo", systemImage: "photo")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(10)
                }
        }
    }
}
