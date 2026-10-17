import SwiftUI
import GreenCore
import GreenCoreFakes

/// AR capture mode (spec §5.1): world-tracked camera, capture a frame, anchor glass labels per component.
struct ARScanView: View {
    let onCapture: (Data, OCRHints) -> Void
    /// Result whose components should be anchored as labels. When nil, the saved scan for the last capture is used.
    var result: ScanResult?
    /// Called when a label is tapped. When nil, the view presents its own component detail sheet.
    var onSelectComponent: ((Component) -> Void)?

    @Environment(AppModel.self) private var model
    @State private var session = ARSessionController()
    @State private var snapshot: ARCaptureSnapshot?
    @State private var isCapturing = false
    @State private var selected: Component?

    init(onCapture: @escaping (Data, OCRHints) -> Void, result: ScanResult? = nil,
         onSelectComponent: ((Component) -> Void)? = nil) {
        self.onCapture = onCapture
        self.result = result
        self.onSelectComponent = onSelectComponent
    }

    var body: some View {
        if ARSessionController.isSupported {
            arContent
        } else {
            ARUnsupportedView { model.flags.scanMode = .photo }
        }
    }

    private var arContent: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(controller: session)
                .ignoresSafeArea()
            if let anchored = anchoredResult {
                ARLabelsOverlay(components: anchored.components, positions: session.labelPositions, onSelect: select)
                    .ignoresSafeArea()
            }
            controls
                .padding(.bottom, model.flags.demoMode ? 150 : 96)
        }
        .onAppear { session.run() }
        .onDisappear { session.pause() }
        .onChange(of: anchoredResult?.id, initial: true) { anchorIfNeeded() }
        .sheet(item: $selected) { component in
            if let anchored = anchoredResult {
                ARComponentDetailSheet(component: component, result: anchored)
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Label(statusMessage, systemImage: statusImage)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .contentTransition(.opacity)
                HStack(spacing: 12) {
                    Button(action: capture) {
                        Label("Capture", systemImage: isCapturing ? "hourglass" : "camera.aperture")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isCapturing || !session.tracking.isReady)
                    if session.anchoredResultID != nil {
                        Button("Clear labels", systemImage: "xmark") { clearLabels() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .animation(.smooth, value: session.tracking)
    }

    private var statusMessage: String {
        if isCapturing { return "Reading labels…" }
        if let anchored = anchoredResult, session.anchoredResultID == anchored.id {
            return session.labelPositions.isEmpty ? "Look around to find your labels" : "Tap a label for details"
        }
        return session.tracking.message
    }

    private var statusImage: String {
        anchoredResult == nil ? session.tracking.systemImage : "tag"
    }

    /// The explicit result, or the saved scan whose photo is this view's last capture.
    private var anchoredResult: ScanResult? {
        if let result { return result }
        guard let jpeg = snapshot?.jpeg else { return nil }
        return model.scans.prefix(5).first { $0.photo == jpeg }
    }

    private func capture() {
        guard let captured = session.capture() else { return }
        isCapturing = true
        session.clearAnchors()
        snapshot = captured
        Task {
            let hints = await ARFrameOCR.hints(for: captured.image)
            isCapturing = false
            onCapture(captured.jpeg, hints)
        }
    }

    private func anchorIfNeeded() {
        guard let anchored = anchoredResult, session.anchoredResultID != anchored.id,
              let camera = snapshot?.camera else { return }
        let total = anchored.components.compactMap { $0.metrics[.carbon]?.value }.reduce(0, +)
        let tints = Dictionary(uniqueKeysWithValues: anchored.components.map { component in
            let share = total > 0 ? (component.metrics[.carbon]?.value ?? 0) / total : 0
            return (component.id, UIColor(Theme.carbonShareTint(share)))
        })
        session.anchor(anchored.components, of: anchored.id, from: camera, tints: tints)
    }

    private func clearLabels() {
        session.clearAnchors()
        snapshot = nil
    }

    private func select(_ component: Component) {
        if let onSelectComponent {
            onSelectComponent(component)
        } else {
            selected = component
        }
    }
}

#Preview {
    ARScanView { _, _ in }
        .environment(AppModel.preview())
}
