@preconcurrency import AVFoundation
import Foundation

/// Whether the back camera can be used.
nonisolated enum CameraAvailability: Equatable, Sendable {
    case checking
    case ready
    /// No camera hardware (e.g. the Simulator).
    case noCamera
    case denied
    case failed(String)
}

nonisolated enum CameraError: LocalizedError {
    case notRunning
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "The camera is not running."
        case let .captureFailed(reason): "Could not take the photo: \(reason)"
        }
    }
}

/// Owns an `AVCaptureSession` with a photo output (spec §5.1 photo mode). Session work runs on a
/// private serial queue; captures are exposed as `async` calls.
nonisolated final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.nv7.LiveGreen.camera")
    private let lock = NSLock()
    private var isConfigured = false
    private var pending: CheckedContinuation<Data, Error>?
    /// Keeps preview and photos horizon-level as the phone rotates (the app supports landscape).
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []
    /// Latest capture angle from the coordinator, which reports on the main queue; read on the session queue.
    private var captureAngle: CGFloat?

    /// Asks for permission if needed, configures the session once and starts it.
    func start() async -> CameraAvailability {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            return .noCamera
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default:
            return .denied
        }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                do {
                    try configureIfNeeded()
                    if !session.isRunning { session.startRunning() }
                    continuation.resume(returning: .ready)
                } catch {
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Starts rotation tracking for `layer`. Call on the main thread once the configured session is attached
    /// to the layer; the coordinator delivers its updates on the main queue.
    @MainActor func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        guard rotation == nil,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotation = coordinator
        Self.apply(coordinator.videoRotationAngleForHorizonLevelPreview, to: layer.connection)
        lock.withLock { captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture }
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { coordinator, _ in
                let layer = coordinator.previewLayer as? AVCaptureVideoPreviewLayer
                Self.apply(coordinator.videoRotationAngleForHorizonLevelPreview, to: layer?.connection)
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                self?.lock.withLock { self?.captureAngle = angle }
            },
        ]
    }

    private static func apply(_ angle: CGFloat, to connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// Takes one still, rotated to how the phone is held, and returns its JPEG data.
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning else {
                    continuation.resume(throwing: CameraError.notRunning)
                    return
                }
                let angle = lock.withLock {
                    pending = continuation
                    return captureAngle
                }
                if let angle { Self.apply(angle, to: output.connection(with: .video)) }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .balanced
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.captureFailed("No back camera")
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.captureFailed("Camera configuration unsupported")
        }
        session.addInput(input)
        session.addOutput(output)
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        output.maxPhotoQualityPrioritization = .balanced
        session.commitConfiguration()
        // Left unset, the output can end up with a size the camera's active format doesn't list, which throws an
        // NSInvalidArgumentException on some devices and iOS versions. Pick one the format supports, once the preset
        // has chosen that format.
        if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            output.maxPhotoDimensions = largest
        }
        isConfigured = true
    }

    private func finish(_ result: Result<Data, Error>) {
        let continuation = lock.withLock {
            defer { pending = nil }
            return pending
        }
        continuation?.resume(with: result)
    }
}

nonisolated extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            finish(.failure(CameraError.captureFailed(error.localizedDescription)))
        } else if let data = photo.fileDataRepresentation() {
            finish(.success(data))
        } else {
            finish(.failure(CameraError.captureFailed("Empty photo")))
        }
    }
}
