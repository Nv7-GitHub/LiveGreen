import SwiftUI
import GreenCore
import GreenCoreFakes

/// AR capture mode (spec §5.1): world-tracked camera, capture a frame, anchor glass labels per component.
/// The anchored labels are the result surface; a label opens the component detail. The Items menu lists every
/// identified item (including ones off screen) and opens the full results screen.
struct ARScanView: View {
    let onCapture: (Data, OCRHints) -> Void
    /// Result whose components should be anchored as labels. When nil, the saved scan for the last capture is used.
    var result: ScanResult?
    /// Called when a label is tapped. When nil, the view presents its own component detail sheet.
    var onSelectComponent: ((Component) -> Void)?
    /// Opens the full results screen for the anchored scan.
    var onOpenResult: ((ScanResult) -> Void)?

    @Environment(AppModel.self) private var model
    @State private var session = ARSessionController()
    @State private var snapshot: ARCaptureSnapshot?
    @State private var isCapturing = false
    @State private var selected: Component?
    /// Global y of the top of the capture controls, so labels stay clear of them.
    @State private var controlsTop: CGFloat?

    init(onCapture: @escaping (Data, OCRHints) -> Void, result: ScanResult? = nil,
         onSelectComponent: ((Component) -> Void)? = nil, onOpenResult: ((ScanResult) -> Void)? = nil) {
        self.onCapture = onCapture
        self.result = result
        self.onSelectComponent = onSelectComponent
        self.onOpenResult = onOpenResult
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
                ARLabelsOverlay(components: anchored.components, positions: session.labelPositions,
                                topInset: session.topBarInset, controlsTop: controlsTop,
                                selectedID: selected?.id, onSelect: select)
                    .ignoresSafeArea()
            }
            controls
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { controlsTop = $0 }
                .padding(.bottom, model.flags.demoMode ? 150 : 96)
        }
        .onAppear { session.run() }
        .onDisappear { session.pause() }
        .onChange(of: anchoredResult?.id, initial: true) { anchorIfNeeded() }
        .sheet(item: $selected) { component in
            if let anchored = anchoredResult {
                ARComponentDetailSheet(component: component, result: anchored, onOpenResult: onOpenResult)
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
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isCapturing || !session.tracking.isReady)
                    .accessibilityIdentifier("arCapture")
                    if let anchored = anchoredResult {
                        itemsMenu(anchored)
                    }
                    if session.anchoredResultID != nil {
                        Button("Clear labels", systemImage: "xmark") { clearLabels() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("arClearLabels")
                    }
                }
                // Large controls: every button in the row is at least 44 pt tall.
                .controlSize(.large)
            }
        }
        .animation(.smooth, value: session.tracking)
    }

    private var statusMessage: String {
        if isCapturing { return "Reading labels…" }
        if let anchored = anchoredResult, session.anchoredResultID == anchored.id {
            return session.labelPositions.isEmpty ? "Look around, or open Items" : "Tap a label or Items for details"
        }
        return session.tracking.message
    }

    /// A dependable way to open any item, even when its label is off screen or crowded, plus the full results.
    private func itemsMenu(_ anchored: ScanResult) -> some View {
        Menu {
            if let onOpenResult {
                Button("Full results", systemImage: "list.bullet.rectangle") { onOpenResult(anchored) }
                    .accessibilityIdentifier("arFullResults")
                Divider()
            }
            ForEach(anchored.components) { component in
                Button(component.name, systemImage: component.category.systemImage) { select(component) }
            }
        } label: {
            Label("Items", systemImage: "list.bullet")
        }
        .menuOrder(.fixed)
        .buttonStyle(.glass)
        .accessibilityIdentifier("arItems")
    }

    private var statusImage: String {
        anchoredResult == nil ? session.tracking.systemImage : "tag"
    }

    /// The explicit result, or the saved scan whose photo is this view's last capture.
    private var anchoredResult: ScanResult? {
        if let result { return result }
        guard let photo = snapshot?.storedPhoto else { return nil }
        return model.scans.prefix(5).first { $0.photo == photo }
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
