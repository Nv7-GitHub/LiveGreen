import SwiftUI

/// Live overlay for the barcode scanner: each barcode in view gets a glowing outline that follows it and a
/// pill with its digits (a checkmark once it reads as a valid retail code). With nothing in view, a soft
/// reticle shows where to aim. Overlay this on the `DataScannerRepresentable` so both share coordinates.
struct BarcodeHighlights: View {
    let barcodes: [TrackedBarcode]
    /// Payloads that parse as retail GTINs; the rest (QR codes, partial reads) are outlined but not checked.
    let accepted: Set<String>

    @State private var pulse = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if barcodes.isEmpty {
                    reticle(in: geometry.size)
                        .transition(.opacity)
                }
                ForEach(barcodes) { barcode in
                    highlight(barcode)
                }
            }
            .animation(.smooth(duration: 0.25), value: barcodes.isEmpty)
        }
        .allowsHitTesting(false)
        .onAppear { pulse = true }
    }

    private func isAccepted(_ barcode: TrackedBarcode) -> Bool {
        barcode.payload.map(accepted.contains) ?? false
    }

    @ViewBuilder private func highlight(_ barcode: TrackedBarcode) -> some View {
        let outline = Quad(corners: barcode.corners)
        let tint = isAccepted(barcode) ? Theme.mint : .white
        outline
            .fill(tint.opacity(0.18))
            .overlay {
                outline.stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .shadow(color: tint.opacity(0.8), radius: 8)
            .animation(.interactiveSpring(duration: 0.15), value: barcode.corners)
        if let payload = barcode.payload, let anchor = labelAnchor(barcode.corners) {
            Label(payload, systemImage: isAccepted(barcode) ? "checkmark.circle.fill" : "barcode")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isAccepted(barcode) ? Theme.leaf : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .fixedSize()
                .position(anchor)
                .animation(.interactiveSpring(duration: 0.15), value: anchor)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// Just below the barcode's lowest corner, centered horizontally.
    private func labelAnchor(_ corners: [CGPoint]) -> CGPoint? {
        guard !corners.isEmpty else { return nil }
        let midX = corners.map(\.x).reduce(0, +) / CGFloat(corners.count)
        let maxY = corners.map(\.y).max() ?? 0
        return CGPoint(x: midX, y: maxY + 22)
    }

    private func reticle(in size: CGSize) -> some View {
        let width = min(size.width * 0.72, 300)
        return CornerBrackets()
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(width: width, height: width * 0.55)
            .shadow(color: .black.opacity(0.4), radius: 4)
            .scaleEffect(pulse ? 1.03 : 0.97)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            .position(x: size.width / 2, y: size.height * 0.4)
    }
}

/// A closed polygon through the given points (a barcode's four corners).
private struct Quad: Shape {
    var corners: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = corners.first else { return path }
        path.move(to: first)
        corners.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

#Preview {
    BarcodeHighlights(
        barcodes: [TrackedBarcode(id: UUID(), payload: "071537003673",
                                  corners: [CGPoint(x: 80, y: 300), CGPoint(x: 300, y: 290),
                                            CGPoint(x: 305, y: 380), CGPoint(x: 85, y: 392)])],
        accepted: ["071537003673"])
        .background(.black)
}
