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

    /// Takes one still and returns its JPEG data.
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning else {
                    continuation.resume(throwing: CameraError.notRunning)
                    return
                }
                lock.withLock { pending = continuation }
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
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CameraError.captureFailed("Camera configuration unsupported")
        }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced
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
