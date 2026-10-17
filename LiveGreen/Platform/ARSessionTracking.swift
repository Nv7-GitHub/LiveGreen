import ARKit

/// User-facing world-tracking state for the AR scan status pill.
nonisolated enum ARTrackingStatus: Equatable, Sendable {
    case initializing
    case normal
    case limited(String)
    case interrupted
    case failed(String)

    init(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal: self = .normal
        case .notAvailable: self = .initializing
        case let .limited(reason):
            switch reason {
            case .excessiveMotion: self = .limited("Slow down")
            case .insufficientFeatures: self = .limited("Point at something with more detail")
            case .relocalizing: self = .limited("Relocalizing…")
            case .initializing: self = .initializing
            @unknown default: self = .limited("Tracking limited")
            }
        }
    }

    var isReady: Bool { self == .normal }

    var message: String {
        switch self {
        case .initializing: "Move your phone slowly to map the scene"
        case .normal: "Frame your items, then capture"
        case let .limited(reason): reason
        case .interrupted: "Integrated view paused"
        case let .failed(message): message
        }
    }

    var systemImage: String {
        switch self {
        case .normal: "checkmark.circle"
        case .initializing, .limited: "move.3d"
        case .interrupted: "pause.circle"
        case .failed: "exclamationmark.triangle"
        }
    }
}
