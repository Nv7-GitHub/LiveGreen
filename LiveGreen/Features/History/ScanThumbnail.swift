import SwiftUI
import UIKit
import GreenCore

/// A downsampled thumbnail of a scan's photo, decoded asynchronously; falls back to the scan mode's symbol.
struct ScanThumbnail: View {
    let scan: ScanResult
    var size: CGFloat = 56

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.title3)
                    .foregroundStyle(Theme.leaf)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.mint.opacity(0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: Theme.hotspotCornerRadius))
        .task(id: scan.id) { await load() }
        .accessibilityHidden(true)
    }

    private var placeholderSymbol: String {
        switch scan.mode {
        case .photo: "photo"
        case .ar: "arkit"
        case .barcode: "barcode"
        }
    }

    private func load() async {
        guard let data = scan.photo, let full = UIImage(data: data) else {
            image = nil
            return
        }
        let pixels = size * 3
        image = await full.byPreparingThumbnail(ofSize: CGSize(width: pixels, height: pixels)) ?? full
    }
}
