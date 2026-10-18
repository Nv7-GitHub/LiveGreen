import SwiftUI
import UIKit
import ImageIO

/// The greener-setup picture: shimmer while generating, retry on failure, before/after slider when ready.
struct GreenerImageView: View {
    let original: Data
    let state: AlternativesModel.ImageState
    /// Where the slider's divider settles so the swapped items show on the greener side.
    var reveal: Double = 0.5
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .generating:
            photo(original)
                .saturation(0.3)
                .shimmering()
                .overlay {
                    Label("Picturing your greener setup…", systemImage: "wand.and.sparkles")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                }
                .clipShape(.rect(cornerRadius: Theme.cardCornerRadius))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Generating the greener image")
        case let .failed(message):
            GlassCard(tint: Theme.danger.opacity(0.15)) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn't generate the image", systemImage: "photo.badge.exclamationmark").font(.headline)
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Text("Your comparison and savings above are unaffected.").font(.caption).foregroundStyle(.secondary)
                    Button("Retry", systemImage: "arrow.clockwise", action: onRetry).buttonStyle(.glassProminent)
                }
            }
        case let .ready(greener):
            BeforeAfterSlider(before: original, after: greener, reveal: reveal)
        }
    }

    private func photo(_ data: Data) -> some View {
        DecodedImage(data: data).photoFrame(aspect: BeforeAfterSlider.aspectRatio(of: data) ?? 4 / 3)
    }
}

extension View {
    /// The photo's proportions at full width, or narrower and centered where that would be taller than
    /// `BeforeAfterSlider.maxHeight`. The cap is on the width, which a scroll view always proposes.
    func photoFrame(aspect: CGFloat) -> some View {
        aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: BeforeAfterSlider.maxHeight * aspect)
    }
}

/// Drag the glass handle to wipe between the original photo and the greener one. Both are drawn into one frame with
/// the photo's proportions, so they line up (G3): the greener edit is redrawn on the photo's frame when it arrives
/// (`GreenerImageFit`), and an older saved one is stretched to it. It opens on the original and wipes to `reveal`,
/// the divider left of every swapped item.
struct BeforeAfterSlider: View {
    let before: Data
    let after: Data
    var reveal: Double = 0.5
    @State private var split: CGFloat = 1
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let space = "beforeAfter"
    /// A tall screenshot stays within one screen, so both tags and the handle are visible together.
    static let maxHeight: CGFloat = 540

    var body: some View {
        Color.clear
            .photoFrame(aspect: Self.aspectRatio(of: before) ?? 4 / 3)
            .overlay {
                GeometryReader { proxy in
                    let x = proxy.size.width * split
                    ZStack(alignment: .topLeading) {
                        DecodedImage(data: after)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        DecodedImage(data: before)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(alignment: .leading) { Rectangle().frame(width: x) }
                        Rectangle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 2, height: proxy.size.height)
                            .position(x: x, y: proxy.size.height / 2)
                        corners
                        handle
                            .position(x: x, y: proxy.size.height / 2)
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                                split = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                            })
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(.rect)
                    .coordinateSpace(.named(Self.space))
                    .onTapGesture(coordinateSpace: .named(Self.space)) { location in
                        withAnimation(.smooth) { split = min(max(location.x / max(proxy.size.width, 1), 0), 1) }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Theme.cardCornerRadius))
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Before and after comparison")
            .accessibilityValue("\(Int(split * 100))% original")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: split = min(split + 0.1, 1)
                case .decrement: split = max(split - 0.1, 0)
                @unknown default: break
                }
            }
            .task {
                guard !revealed else { return }
                revealed = true
                if reduceMotion {
                    split = reveal
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeInOut(duration: 1.1)) { split = reveal }
            }
    }

    /// Width over height of the photo as shown, read from its header without decoding it.
    static func aspectRatio(of data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double, width > 0, height > 0 else { return nil }
        // EXIF orientations 5–8 are rotated a quarter turn.
        let rotated = (properties[kCGImagePropertyOrientation] as? Int).map { (5...8).contains($0) } ?? false
        return rotated ? height / width : width / height
    }

    private var handle: some View {
        Image(systemName: "chevron.left.chevron.right")
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    private var corners: some View {
        VStack {
            HStack {
                tag("Before")
                Spacer()
                tag("Greener")
            }
            Spacer()
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Renders JPEG/PNG bytes, with a neutral placeholder for undecodable data.
struct DecodedImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable()
        } else {
            Rectangle().fill(.quaternary).aspectRatio(4 / 3, contentMode: .fit)
                .overlay { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
        }
    }
}

#Preview("Ready") {
    BeforeAfterSlider(before: AlternativesPreviewData.photo(tint: .brown),
                      after: AlternativesPreviewData.photo(tint: .green))
        .padding()
}

#Preview("States") {
    ScrollView {
        VStack(spacing: 20) {
            GreenerImageView(original: AlternativesPreviewData.photo(tint: .brown), state: .generating) {}
            GreenerImageView(original: AlternativesPreviewData.photo(tint: .brown),
                             state: .failed("The image service took too long.")) {}
        }
        .padding()
    }
}
