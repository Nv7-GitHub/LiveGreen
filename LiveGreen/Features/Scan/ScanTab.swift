import SwiftUI
import GreenCore
import GreenCoreFakes

/// Default tab: capture (Photo / AR / Barcode), analyzing progress, then results (spec §10).
struct ScanTab: View {
    @Environment(AppModel.self) private var model
    @State private var phase: Phase = .capture
    @State private var events: AsyncThrowingStream<PipelineEvent, Error>?
    @State private var runID = UUID()
    @State private var path: [ScanResult] = []
    /// The last capture sent to the pipeline, so a failed scan can be retried without retaking it.
    @State private var lastCapture: Capture?
    @Namespace private var glass

    struct Capture {
        var image: Data
        var hints: OCRHints
        var scene: DemoScene?
        var mode: ScanMode
    }

    enum Phase: Equatable {
        case capture
        case analyzing
        case failed(String)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                captureView
                    .ignoresSafeArea(edges: .top)
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 12) {
                        switch phase {
                        case .capture:
                            if model.flags.demoMode { demoButtons }
                            modePicker
                        case .analyzing:
                            if let events {
                                AnalyzingCard(events: events, onComplete: finish, onFailure: fail)
                                    .id(runID)
                                    .glassEffectID("status", in: glass)
                            }
                        case let .failed(message):
                            failureCard(message)
                                .glassEffectID("status", in: glass)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Scan")
            .toolbarTitleDisplayMode(.inline)
            .settingsToolbarButton()
            .navigationDestination(for: ScanResult.self) { ScanResultView(result: $0) }
            .animation(.smooth, value: phase)
        }
    }

    @ViewBuilder private var captureView: some View {
        switch model.flags.scanMode {
        case .photo: PhotoScanView { image, hints in start(image: image, hints: hints) }
        case .ar:
            ARScanView(onCapture: { image, hints in start(image: image, hints: hints) },
                       onOpenResult: { path.append($0) })
        case .barcode: BarcodeLabelScanner { hints in start(image: Data(), hints: hints) }
        }
    }

    private var modePicker: some View {
        @Bindable var model = model
        return Picker("Scan mode", selection: $model.flags.scanMode) {
            ForEach(ScanMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("modes", in: glass)
    }

    private var demoButtons: some View {
        HStack {
            ForEach(DemoScene.allCases, id: \.self) { scene in
                Button(scene.title) { start(image: DemoArtwork.photo(for: scene), hints: .none, scene: scene) }
                    .buttonStyle(.glass)
            }
        }
        .glassEffectID("demo", in: glass)
    }

    private func failureCard(_ message: String) -> some View {
        GlassCard(tint: Theme.danger.opacity(0.2)) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Scan failed", systemImage: "exclamationmark.triangle").font(.headline)
                Text(message).font(.footnote).foregroundStyle(.secondary)
                HStack {
                    if let lastCapture {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            start(image: lastCapture.image, hints: lastCapture.hints, scene: lastCapture.scene)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("retryScan")
                    }
                    Button("New scan", systemImage: "camera") { phase = .capture }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private func start(image: Data, hints: OCRHints, scene: DemoScene? = nil) {
        lastCapture = Capture(image: image, hints: hints, scene: scene, mode: model.flags.scanMode)
        let coordinator = model.makeScanCoordinator(scene: scene)
        events = coordinator.scan(image: image, hints: hints)
        runID = UUID()
        phase = .analyzing
    }

    /// AR captures stay on the AR view, whose anchored labels are the result surface (spec §5.1); every
    /// other scan opens the results screen.
    private func finish(_ result: ScanResult) {
        model.save(result)
        let anchorsInAR = lastCapture?.mode == .ar && lastCapture?.scene == nil && model.flags.scanMode == .ar
        if !anchorsInAR { path.append(result) }
        lastCapture = nil
        events = nil
        phase = .capture
    }

    private func fail(_ error: any Error) {
        events = nil
        phase = .failed(error.localizedDescription)
    }
}

#Preview {
    ScanTab().environment(AppModel.preview())
}
