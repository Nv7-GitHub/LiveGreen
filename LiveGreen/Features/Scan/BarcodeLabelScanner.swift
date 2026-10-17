import SwiftUI
import GreenCore

/// Barcode / label mode (spec §5.1): live barcodes and text via `DataScannerViewController` for
/// packaged goods and appliance labels. Detected identifiers accumulate in a glass panel; "Look up"
/// hands them to the pipeline as `OCRHints`. Falls back to manual GTIN entry when live scanning is
/// unavailable (Simulator, no camera permission).
struct BarcodeLabelScanner: View {
    let onScan: (OCRHints) -> Void

    @State private var payloads: [String] = []
    @State private var lines: [String] = []
    @State private var manualCode = ""
    @State private var isLive = DataScannerRepresentable.isReady

    private let bottomClearance: CGFloat = 96
    /// Keeps the parser input bounded while a label stays in view.
    private let maxLines = 80

    private var hints: OCRHints {
        OCRTextParser.hints(barcodePayloads: payloads, textLines: lines)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isLive {
                DataScannerRepresentable(onBarcode: addPayload, onText: addText)
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [Theme.moss, .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            panel
                .padding(.horizontal)
                .padding(.bottom, bottomClearance)
        }
        .animation(.smooth, value: hints)
        .task { isLive = await DataScannerRepresentable.requestAccessIfNeeded() }
    }

    @ViewBuilder private var panel: some View {
        if isLive {
            livePanel
        } else {
            manualPanel
        }
    }

    // MARK: - Live

    private var livePanel: some View {
        let hints = hints
        let found = DetectedIdentifier.list(from: hints)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(found.isEmpty ? "Point at a barcode or appliance label" : "Found on the label",
                      systemImage: "barcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                if !found.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(found) { item in
                                Label(item.text, systemImage: item.systemImage)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .glassEffect(.regular.tint(Theme.leaf.opacity(0.25)), in: .capsule)
                            }
                        }
                    }
                }
                HStack {
                    Button("Clear", systemImage: "xmark") { reset() }
                        .buttonStyle(.glass)
                        .disabled(found.isEmpty)
                    Spacer()
                    Button("Look up", systemImage: "magnifyingglass") {
                        onScan(hints)
                        reset()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(found.isEmpty)
                    .accessibilityIdentifier("barcodeLookUp")
                }
            }
        }
    }

    private func addPayload(_ payload: String) {
        guard !payloads.contains(payload) else { return }
        payloads.append(payload)
    }

    private func addText(_ transcript: String) {
        let newLines = transcript.split(whereSeparator: \.isNewline).map(String.init).filter { !lines.contains($0) }
        guard !newLines.isEmpty else { return }
        lines = Array((lines + newLines).suffix(maxLines))
    }

    private func reset() {
        payloads = []
        lines = []
    }

    // MARK: - Manual fallback

    private var manualPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Live scanning isn't available here. Type the number under the barcode.",
                      systemImage: "barcode")
                    .font(.subheadline)
                TextField("GTIN / barcode", text: $manualCode)
                    .keyboardType(.numberPad)
                    .padding(12)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityIdentifier("manualGTIN")
                Button("Look up", systemImage: "magnifyingglass") {
                    let digits = manualCode.filter(\.isNumber)
                    onScan(OCRHints(gtins: [digits]))
                    manualCode = ""
                }
                .buttonStyle(.glassProminent)
                .disabled(!OCRTextParser.gtinLengths.contains(manualCode.filter(\.isNumber).count))
            }
        }
    }
}

/// One identifier chip shown in the scanner panel.
private struct DetectedIdentifier: Identifiable {
    let id: String
    let text: String
    let systemImage: String

    static func list(from hints: OCRHints) -> [DetectedIdentifier] {
        hints.gtins.map { DetectedIdentifier(id: "g\($0)", text: $0, systemImage: "barcode") }
            + hints.modelNumbers.map { DetectedIdentifier(id: "m\($0)", text: $0, systemImage: "number") }
            + hints.wattages.map {
                DetectedIdentifier(id: "w\($0)", text: "\(Measured.format($0)) W", systemImage: "bolt")
            }
            + hints.fiberPercentages.map {
                DetectedIdentifier(id: "f\($0.material)", text: "\(Int($0.percent))% \($0.material)", systemImage: "tshirt")
            }
            + hints.resinCodes.map { DetectedIdentifier(id: "r\($0)", text: "Resin \($0)", systemImage: "arrow.3.trianglepath") }
    }
}

#Preview {
    BarcodeLabelScanner { print($0) }
}
