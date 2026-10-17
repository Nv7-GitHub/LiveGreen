import SwiftUI
import PhotosUI
import GreenCore

/// Photo capture mode (spec §5.1): live camera with a glass shutter, or a PhotosPicker import. The
/// captured still is shown full-bleed while the on-device Vision pre-pass runs, then JPEG data and
/// OCR hints are handed to the pipeline. Without a camera (Simulator) it offers the picker and a
/// sample photo.
struct PhotoScanView: View {
    let onCapture: (Data, OCRHints) -> Void

    @State private var camera = CameraController()
    @State private var availability: CameraAvailability = .checking
    @State private var selection: PhotosPickerItem?
    @State private var still: UIImage?
    @State private var isReading = false
    @State private var errorMessage: String?
    @Namespace private var controls

    /// Leaves room for the scan tab's mode switch and the floating tab bar below these controls.
    private let bottomClearance: CGFloat = 96

    var body: some View {
        ZStack {
            background
            VStack(spacing: 12) {
                Spacer()
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.tint(Theme.danger.opacity(0.3)), in: .capsule)
                }
                if isReading {
                    Label("Reading labels…", systemImage: "text.viewfinder")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.opacity)
                }
                controlRow
            }
            .padding(.bottom, bottomClearance)
            .padding(.horizontal)
        }
        .animation(.smooth, value: still != nil)
        .animation(.smooth, value: isReading)
        .task {
            availability = await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            selection = nil
            Task { await importPhoto(item) }
        }
    }

    // MARK: - Background

    @ViewBuilder private var background: some View {
        if let still {
            Color.black.overlay {
                Image(uiImage: still)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityLabel("Captured photo")
        } else {
            switch availability {
            case .ready:
                CameraPreview(session: camera.session).ignoresSafeArea()
            case .checking:
                Color.black.ignoresSafeArea()
            case .noCamera, .denied, .failed:
                fallback
            }
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [Theme.moss, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.8))
                Text(fallbackMessage)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 32)
                if availability == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url).buttonStyle(.glass)
                }
            }
            .padding(.bottom, 120)
        }
    }

    private var fallbackMessage: String {
        switch availability {
        case .denied: "Camera access is off. Allow it in Settings, or pick a photo instead."
        case let .failed(reason): "The camera could not start (\(reason)). Pick a photo instead."
        default: "No camera on this device. Pick a photo or try the sample desk."
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 20) {
                if still != nil {
                    Button("Retake", systemImage: "arrow.counterclockwise") { retake() }
                        .buttonStyle(.glass)
                        .glassEffectID("secondary", in: controls)
                        .disabled(isReading)
                    libraryPicker(compact: false)
                } else if availability == .ready {
                    libraryPicker(compact: true)
                    shutterButton
                    Color.clear.frame(width: 52, height: 52)
                } else if availability != .checking {
                    libraryPicker(compact: false)
                    Button("Sample photo", systemImage: "sparkles.rectangle.stack") {
                        Task { await process(SamplePhoto.deskJPEG()) }
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("secondary", in: controls)
                    .accessibilityIdentifier("samplePhotoButton")
                }
            }
        }
    }

    private var shutterButton: some View {
        Button {
            Task { await capture() }
        } label: {
            Image(systemName: "camera.fill")
                .font(.title2)
                .frame(width: 72, height: 72)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .glassEffectID("primary", in: controls)
        .accessibilityLabel("Take photo")
        .accessibilityIdentifier("shutterButton")
    }

    @ViewBuilder private func libraryPicker(compact: Bool) -> some View {
        let picker = PhotosPicker(selection: $selection, matching: .images) {
            if compact {
                Image(systemName: "photo.on.rectangle").font(.title3).frame(width: 52, height: 52)
            } else {
                Label("Choose photo", systemImage: "photo.on.rectangle")
            }
        }
        .accessibilityLabel("Choose a photo")
        if compact {
            picker.buttonStyle(.glass).buttonBorderShape(.circle).glassEffectID("library", in: controls)
        } else {
            picker.buttonStyle(.glassProminent).glassEffectID("library", in: controls)
        }
    }

    // MARK: - Actions

    private func capture() async {
        errorMessage = nil
        do {
            let data = try await camera.capturePhoto()
            camera.stop()
            await process(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "That photo could not be loaded."
                return
            }
            camera.stop()
            await process(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Normalizes the image, shows it full-bleed, runs the Vision pre-pass, then hands off.
    private func process(_ raw: Data) async {
        guard let jpeg = await Task.detached(operation: { CapturedImage.normalizedJPEG(from: raw) }).value,
              let image = UIImage(data: jpeg) else {
            errorMessage = "That image format is not supported."
            return
        }
        still = image
        isReading = true
        let hints = await VisionOCR.hints(for: jpeg)
        isReading = false
        onCapture(jpeg, hints)
    }

    private func retake() {
        still = nil
        errorMessage = nil
        Task { availability = await camera.start() }
    }
}

#Preview {
    PhotoScanView { _, hints in print(hints) }
}
