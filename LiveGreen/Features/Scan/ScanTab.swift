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
    /// The running scan's coordinator, kept to refine the result with detail answers.
    @State private var coordinator: ScanCoordinator?
    /// Detail questions the running scan raised for items still on a T4 estimate.
    @State private var specQuestions: [SpecQuestion] = []
    /// The finished scan waiting on the detail questions sheet.
    @State private var specPrompt: SpecPrompt?
    /// What to open once the sheet is gone (the estimate, or the refined result), so the push follows the dismissal.
    @State private var resultAfterPrompt: ScanResult?
    /// A finished store or street scan waiting on "Which is yours?".
    @State private var ownershipPrompt: ScanResult?
    /// The scan to continue with once that sheet is gone: as identify guessed, or as the user sorted it.
    @State private var resultAfterOwnership: ScanResult?
    @Namespace private var glass

    struct Capture {
        var image: Data
        var hints: OCRHints
        var scene: DemoScene?
        var mode: ScanMode
    }

    struct SpecPrompt: Identifiable {
        var result: ScanResult
        var questions: [SpecQuestion]
        var id: UUID { result.id }
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
                                AnalyzingCard(events: events, onSpecQuestions: { specQuestions = $0 },
                                              onComplete: finish, onFailure: fail)
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
            .sheet(item: $ownershipPrompt, onDismiss: continueAfterOwnership) { result in
                WhichIsYoursSheet(result: result) { owned in
                    resultAfterOwnership = coordinator?.markingOwned(only: owned, in: result) ?? result
                    ownershipPrompt = nil
                }
            }
            .sheet(item: $specPrompt, onDismiss: openResultAfterPrompt) { prompt in
                SpecQuestionsSheet(questions: prompt.questions,
                                   onApply: { refine(prompt.result, with: $0) },
                                   onSkip: { specPrompt = nil })
            }
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
        self.coordinator = coordinator
        specQuestions = []
        events = coordinator.scan(image: image, hints: hints)
        runID = UUID()
        phase = .analyzing
    }

    /// A store or street scan first asks which items are the user's; then items still on a T4 estimate get the detail
    /// questions sheet; everything else opens straight away.
    private func finish(_ result: ScanResult) {
        guard result.asksWhichIsYours else { return askDetails(result) }
        resultAfterOwnership = result
        ownershipPrompt = result
    }

    private func continueAfterOwnership() {
        guard let result = resultAfterOwnership else { return }
        resultAfterOwnership = nil
        askDetails(result)
    }

    /// Detail questions only about items the results count: none about a stranger's car or the store's stock.
    private func askDetails(_ result: ScanResult) {
        let questions = specQuestions.filter { question in
            result.component(withID: question.componentID).map(result.isTotaled) ?? false
        }
        specQuestions = []
        guard !questions.isEmpty else { return show(result) }
        resultAfterPrompt = result
        specPrompt = SpecPrompt(result: result, questions: questions)
    }

    /// Re-resolves the answered items on-device, then closes the sheet; the dismissal opens the refined result.
    private func refine(_ result: ScanResult, with answers: [SpecAnswer]) {
        Task {
            let refined = await coordinator?.refining(result, specAnswers: answers) ?? result
            guard specPrompt?.id == result.id else { return }
            resultAfterPrompt = refined
            specPrompt = nil
        }
    }

    private func openResultAfterPrompt() {
        guard let result = resultAfterPrompt else { return }
        resultAfterPrompt = nil
        show(result)
    }

    /// AR captures stay on the AR view, whose anchored labels are the result surface (spec §5.1); every
    /// other scan opens the results screen.
    private func show(_ result: ScanResult) {
        model.save(result)
        let anchorsInAR = lastCapture?.mode == .ar && lastCapture?.scene == nil && model.flags.scanMode == .ar
        if !anchorsInAR { path.append(result) }
        lastCapture = nil
        coordinator = nil
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
