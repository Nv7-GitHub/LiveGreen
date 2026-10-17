import ARKit
import Combine
import Observation
import RealityKit
import UIKit
import GreenCore

/// Owns the RealityKit `ARView` for AR scan mode: world tracking with plane detection, frame capture,
/// raycast anchoring of identified components, and per-frame projection of anchors to screen points.
@Observable
final class ARSessionController: NSObject {
    /// Whether this device can run world tracking (false in the Simulator).
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private(set) var tracking: ARTrackingStatus = .initializing
    /// Screen position of each anchored component's label, refreshed every frame; absent when off-screen.
    private(set) var labelPositions: [UUID: CGPoint] = [:]
    /// The scan whose components are currently anchored.
    private(set) var anchoredResultID: UUID?

    @ObservationIgnored private(set) lazy var arView: ARView = makeView()
    @ObservationIgnored private var anchors: [UUID: AnchorEntity] = [:]
    @ObservationIgnored private var updateSubscription: (any Cancellable)?
    @ObservationIgnored private var isRunning = false

    /// Distance used when no surface can be found along a component's ray.
    private static let fallbackDepth: Float = 0.75

    func run() {
        guard Self.isSupported, !isRunning else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        arView.session.run(configuration)
        isRunning = true
        if updateSubscription == nil {
            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.projectLabels()
            }
        }
    }

    func pause() {
        guard isRunning else { return }
        arView.session.pause()
        isRunning = false
    }

    /// Grabs the current camera frame as an upright JPEG plus its camera pose.
    func capture() -> ARCaptureSnapshot? {
        guard let frame = arView.session.currentFrame else { return nil }
        return ARCaptureSnapshot.make(from: frame, orientation: interfaceOrientation)
    }

    /// Raycasts each component's box center from the captured camera and anchors a pin there.
    func anchor(_ components: [GreenCore.Component], of resultID: UUID, from camera: ARCapturedCamera, tints: [UUID: UIColor]) {
        clearAnchors()
        anchoredResultID = resultID
        for component in components {
            let center = CGPoint(x: component.boundingBox.clamped.midX, y: component.boundingBox.clamped.midY)
            let anchor = AnchorEntity(world: worldTransform(for: center, from: camera))
            anchor.addChild(Self.pin(color: tints[component.id] ?? .systemGreen))
            arView.scene.addAnchor(anchor)
            anchors[component.id] = anchor
        }
        projectLabels()
    }

    func clearAnchors() {
        anchors.values.forEach { arView.scene.removeAnchor($0) }
        anchors = [:]
        labelPositions = [:]
        anchoredResultID = nil
    }

    // MARK: - Raycasting

    /// `.estimatedPlane` first, then `.existingPlaneGeometry`, else a point at a fixed depth along the ray.
    private func worldTransform(for uprightPoint: CGPoint, from camera: ARCapturedCamera) -> simd_float4x4 {
        let ray = camera.ray(throughUpright: uprightPoint)
        for target in [ARRaycastQuery.Target.estimatedPlane, .existingPlaneGeometry] {
            let query = ARRaycastQuery(origin: ray.origin, direction: ray.direction, allowing: target, alignment: .any)
            if let hit = arView.session.raycast(query).first { return hit.worldTransform }
        }
        var transform = matrix_identity_float4x4
        let point = ray.origin + ray.direction * Self.fallbackDepth
        transform.columns.3 = SIMD4(point.x, point.y, point.z, 1)
        return transform
    }

    // MARK: - Projection

    private func projectLabels() {
        guard !anchors.isEmpty, let camera = arView.session.currentFrame?.camera else {
            if !labelPositions.isEmpty { labelPositions = [:] }
            return
        }
        let cameraPosition = SIMD3(camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
        let forward = -SIMD3(camera.transform.columns.2.x, camera.transform.columns.2.y, camera.transform.columns.2.z)
        let bounds = arView.bounds
        var positions: [UUID: CGPoint] = [:]
        for (id, anchor) in anchors {
            let world = anchor.position(relativeTo: nil)
            guard simd_dot(world - cameraPosition, forward) > 0,
                  let point = arView.project(world),
                  bounds.insetBy(dx: -40, dy: -40).contains(point) else { continue }
            positions[id] = point
        }
        if positions.count != labelPositions.count || positions.contains(where: { id, point in
            guard let old = labelPositions[id] else { return true }
            return abs(old.x - point.x) > 0.5 || abs(old.y - point.y) > 0.5
        }) {
            labelPositions = positions
        }
    }

    // MARK: - Setup

    private var interfaceOrientation: UIInterfaceOrientation {
        arView.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }

    private func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions.insert(.disableMotionBlur)
        view.session.delegate = self
        return view
    }

    private static func pin(color: UIColor) -> ModelEntity {
        let material = SimpleMaterial(color: color, roughness: 0.3, isMetallic: false)
        return ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [material])
    }
}

extension ARSessionController: @MainActor ARSessionDelegate {
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        tracking = ARTrackingStatus(camera.trackingState)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        tracking = .interrupted
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        tracking = .initializing
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        tracking = .failed(error.localizedDescription)
        isRunning = false
    }
}
