import SwiftUI

/// An empty state drawn like a page of a field journal: the illustration, a specimen label with the title in serif
/// italics and a typewriter caption, then the explanation and actions.
struct GreeneryEmptyState<Actions: View>: View {
    let art: GreeneryArt
    let title: String
    /// A few words in small capitals under the title, like the label on a pressed specimen.
    let caption: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            art.image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 190, maxHeight: 170)
                .swaying(1.5, anchor: .bottom, duration: 4.5)
                .accessibilityHidden(true)
            SpecimenLabel(title: title, caption: caption)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 420)
    }
}

extension GreeneryEmptyState where Actions == EmptyView {
    init(art: GreeneryArt, title: String, caption: String, message: String) {
        self.init(art: art, title: title, caption: caption, message: message) { EmptyView() }
    }
}

/// A cream specimen tag: a serif italic name over a spaced-out caption, the same in light and dark mode, like a
/// label pinned beside a pressed flower.
struct SpecimenLabel: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(caption.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(Theme.moss)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.labelCream, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.moss.opacity(0.35), lineWidth: 1.5)
                .padding(3)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

#Preview {
    GreeneryEmptyState(art: .seedling, title: "No scans yet", caption: "Awaiting first specimen",
                       message: "Scans you save appear here.") {
        Button("Start scanning", systemImage: "viewfinder") {}
            .buttonStyle(.glassProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .greeneryBackground(.history)
}
