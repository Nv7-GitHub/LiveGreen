/// Size limits for the photo sent to identify (spec §5.3). Claude Sonnet 5.5 and Opus 5.5 read images up to
/// 2576 px on the long edge and about 3.75 megapixels (~4,800 image tokens); larger images are downscaled by the
/// API, so sending more only costs upload time. The old 1568 px cap (earlier models' limit) blurred the small
/// detail that names a product: keyboard legends, logos, the line name printed under a screen.
public enum IdentifyImage {
    public static let maxLongEdge = 2576.0
    /// Just under the API's 3.75 MP limit, so rounding to whole pixels never pushes an image over it.
    public static let maxPixels = 3_700_000.0

    /// The largest whole-pixel size within both limits with the same aspect ratio; images that fit are never upscaled.
    public static func fittedSize(width: Double, height: Double) -> (width: Double, height: Double) {
        guard width > 0, height > 0 else { return (0, 0) }
        let scale = min(1, maxLongEdge / max(width, height), (maxPixels / (width * height)).squareRoot())
        return ((width * scale).rounded(), (height * scale).rounded())
    }
}
