import ARKit
import CoreImage
import UIKit
import simd

/// Camera pose and geometry frozen at the moment of capture, so component boxes that arrive seconds later
/// are raycast from where the camera was, not where it is now.
nonisolated struct ARCapturedCamera: Sendable {
    let transform: simd_float4x4
    let intrinsics: simd_float3x3
    /// Sensor image size in pixels (landscape).
    let imageResolution: CGSize
    /// Maps normalized upright-photo coordinates (top-left origin) to normalized sensor-image coordinates.
    let uprightToSensor: CGAffineTransform

    var position: SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    /// World-space ray through a normalized point of the upright photo.
    func ray(throughUpright point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let sensor = point.applying(uprightToSensor)
        let px = Float(sensor.x * imageResolution.width)
        let py = Float(sensor.y * imageResolution.height)
        let fx = intrinsics.columns.0.x, fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x, cy = intrinsics.columns.2.y
        // ARKit camera space: +x right, +y up, -z forward; pixel rows grow downward.
        let local = SIMD4<Float>((px - cx) / fx, -(py - cy) / fy, -1, 0)
        let world = transform * local
        return (position, simd_normalize(SIMD3(world.x, world.y, world.z)))
    }
}

/// One captured AR frame: an upright JPEG for the pipeline plus the camera it came from.
struct ARCaptureSnapshot {
    let jpeg: Data
    let image: CGImage
    let camera: ARCapturedCamera

    private static let context = CIContext()

    /// Converts `frame.capturedImage` (landscape sensor buffer) into an upright JPEG for `orientation`, with
    /// the long edge capped like photo mode (spec §5.3). Boxes are normalized, so anchoring is unaffected.
    static func make(from frame: ARFrame, orientation: UIInterfaceOrientation) -> ARCaptureSnapshot? {
        let resolution = frame.camera.imageResolution
        let imageOrientation = orientation.capturedImageOrientation
        let upright = CIImage(cvPixelBuffer: frame.capturedImage).oriented(imageOrientation)
        guard let cgImage = context.createCGImage(upright, from: upright.extent),
              let jpeg = CapturedImage.normalizedJPEG(from: UIImage(cgImage: cgImage), quality: 0.82)
        else { return nil }

        // With a viewport of the photo's own aspect, displayTransform is a pure rotation sensor → upright.
        let uprightSize = orientation.isPortrait
            ? CGSize(width: resolution.height, height: resolution.width)
            : resolution
        let sensorToUpright = frame.displayTransform(for: orientation, viewportSize: uprightSize)
        let camera = ARCapturedCamera(transform: frame.camera.transform, intrinsics: frame.camera.intrinsics,
                                      imageResolution: resolution, uprightToSensor: sensorToUpright.inverted())
        return ARCaptureSnapshot(jpeg: jpeg, image: cgImage, camera: camera)
    }
}

extension UIInterfaceOrientation {
    /// Rotation that turns the back camera's landscape-right sensor buffer upright for this interface orientation.
    nonisolated var capturedImageOrientation: CGImagePropertyOrientation {
        switch self {
        case .portrait: .right
        case .portraitUpsideDown: .left
        case .landscapeLeft: .down
        case .landscapeRight: .up
        default: .right
        }
    }
}
