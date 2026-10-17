import SwiftUI
import GreenCore

/// Barcode / label mode (spec §5.1): live barcodes and text for packaged goods and appliance labels.
struct BarcodeLabelScanner: View {
    let onScan: (OCRHints) -> Void
    @State private var code = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.moss, .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 16) {
                Image(systemName: "barcode.viewfinder").font(.system(size: 64)).foregroundStyle(.white.opacity(0.8))
                TextField("GTIN / barcode", text: $code)
                    .keyboardType(.numberPad)
                    .padding()
                    .glassEffect(.regular, in: .capsule)
                    .frame(maxWidth: 280)
                Button("Look up", systemImage: "magnifyingglass") {
                    onScan(OCRHints(gtins: [code]))
                    code = ""
                }
                .buttonStyle(.glassProminent)
                .disabled(code.count < 8)
            }
        }
    }
}

#Preview {
    BarcodeLabelScanner { _ in }
}
