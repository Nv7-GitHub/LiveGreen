import SwiftUI
import UIKit
import GreenCore

/// The captured still at its own aspect ratio, so normalized boxes map onto it directly. Barcode scans
/// show the product's pack shot from its record; scans without any photo get a neutral 4:3 backdrop.
struct ResultPhoto: View {
    let data: Data?
    var mode: ScanMode = .photo

    private var image: UIImage? { data.flatMap(UIImage.init(data:)) }

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
            } else {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityLabel("Scanned photo")
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
        }
    }
}
