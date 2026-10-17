import SwiftUI
import GreenCore
import GreenCoreFakes

/// Default tab: capture (Photo / AR / Barcode), analyzing progress, then results (spec §10).
struct ScanTab: View {
    @Environment(AppModel.self) private var model
    @State private var phase: Phase = .capture
    @State private var progress = PipelineProgress()
    @State private var path: [ScanResult] = []
    @Namespace private var glass

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
                            PipelineProgressCard(progress: progress)
                                .glassEffectID("status", in: glass)
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
        case .ar: ARScanView { image, hints in start(image: image, hints: hints) }
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
                Button("Try again") { phase = .capture }.buttonStyle(.glassProminent)
            }
        }
    }

    private func start(image: Data, hints: OCRHints, scene: DemoScene? = nil) {
        let coordinator = model.makeScanCoordinator(scene: scene)
        progress = PipelineProgress()
        phase = .analyzing
        Task {
            do {
                for try await event in coordinator.scan(image: image, hints: hints) {
                    progress.apply(event)
                    if case let .completed(result) = event {
                        model.save(result)
                        path.append(result)
                    }
                }
                phase = .capture
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

#Preview {
    ScanTab().environment(AppModel.preview())
}
