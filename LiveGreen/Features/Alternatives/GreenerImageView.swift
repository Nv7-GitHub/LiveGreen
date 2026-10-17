import SwiftUI
import UIKit

/// The greener-setup picture: shimmer while generating, retry on failure, before/after slider when ready.
struct GreenerImageView: View {
    let original: Data
    let state: AlternativesModel.ImageState
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
            BeforeAfterSlider(before: original, after: greener)
        }
    }

    private func photo(_ data: Data) -> some View {
        DecodedImage(data: data).aspectRatio(contentMode: .fit)
    }
}

/// Drag the glass handle to wipe between the original photo and the greener one.
struct BeforeAfterSlider: View {
    let before: Data
    let after: Data
    @State private var split: CGFloat = 0.5
    private static let space = "beforeAfter"

    var body: some View {
        DecodedImage(data: after)
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let x = proxy.size.width * split
                    ZStack(alignment: .topLeading) {
                        DecodedImage(data: before)
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
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
