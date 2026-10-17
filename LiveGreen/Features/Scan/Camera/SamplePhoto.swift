import SwiftUI
import UIKit

/// A rendered stand-in photo of the demo desk scene, laid out to match the desk fixture's bounding
/// boxes. Used where no camera exists (Simulator) and in previews.
enum SamplePhoto {
    static let size = CGSize(width: 1200, height: 900)

    /// JPEG of the sample desk scene.
    static func deskJPEG() -> Data {
        let renderer = ImageRenderer(content: DeskIllustration().frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.uiImage?.jpegData(compressionQuality: 0.85) ?? Data()
    }
}

/// Simple vector desk: lamp, monitor, laptop and a coffee cup, positioned in normalized coordinates.
private struct DeskIllustration: View {
    private let w = SamplePhoto.size.width
    private let h = SamplePhoto.size.height

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(white: 0.86), Color(red: 0.78, green: 0.80, blue: 0.76)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.46, blue: 0.32),
                                              Color(red: 0.48, green: 0.34, blue: 0.23)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: h * 0.42)
                .offset(y: h * 0.58)
            lamp
            monitor
            laptop
            cup
        }
        .frame(width: w, height: h)
    }

    private func place<V: View>(_ x: Double, _ y: Double, _ width: Double, _ height: Double,
                                @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: w * width, height: h * height)
            .offset(x: w * x, y: h * y)
    }

    private var monitor: some View {
        place(0.25, 0.08, 0.50, 0.34) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.7),
                                                          Color(red: 0.55, green: 0.75, blue: 0.85)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .padding(10))
                Rectangle().fill(Color(white: 0.2)).frame(width: 36, height: 28)
            }
        }
    }

    private var laptop: some View {
        place(0.30, 0.45, 0.40, 0.32) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.7))
                    .overlay(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.15)).padding(8))
                    .padding(.horizontal, 24)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.78))
                    .frame(height: 34)
            }
        }
    }

    private var cup: some View {
        place(0.78, 0.52, 0.12, 0.20) {
            VStack(spacing: 0) {
                Capsule().fill(Color(white: 0.25)).frame(height: 18)
                UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                    .fill(Color(white: 0.96))
                    .overlay(Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.25)).frame(height: 30))
                    .padding(.horizontal, 8)
            }
        }
    }

    private var lamp: some View {
        place(0.05, 0.20, 0.16, 0.50) {
            VStack(spacing: 0) {
                Capsule().fill(Color(white: 0.2)).frame(height: 46)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(Color(red: 1, green: 0.95, blue: 0.7)).frame(height: 10).padding(.horizontal, 10)
                    }
                Rectangle().fill(Color(white: 0.3)).frame(width: 10)
                Capsule().fill(Color(white: 0.2)).frame(height: 22)
            }
        }
    }
}

#Preview {
    Image(uiImage: UIImage(data: SamplePhoto.deskJPEG()) ?? UIImage())
        .resizable()
        .scaledToFit()
}
