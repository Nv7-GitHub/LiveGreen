import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GreenCore

/// The greener edit is put on the photo's own frame (G3 of the image QA), whichever way the image model fitted the
/// photo into its square output.
@Suite("Greener image fit")
struct GreenerImageFitTests {
    /// A portrait "photo" with features at distinct places, so a misaligned mapping differs clearly.
    static func photo(width: Int = 300, height: Int = 400) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for row in 0..<20 {
            let shade = CGFloat(row) / 20
            context.setFillColor(CGColor(srgbRed: shade, green: 0.5 * shade, blue: 1 - shade, alpha: 1))
            context.fill(CGRect(x: 0, y: row * height / 20, width: width, height: height / 20 + 1))
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 20, y: 30, width: 60, height: 50))
        context.fill(CGRect(x: 200, y: 300, width: 70, height: 40))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 120, y: 150, width: 40, height: 120))
        return context.makeImage()!
    }

    /// `image`'s part drawn into a `size`×`size` square, optionally inside a smaller rect with black bands.
    static func square(_ image: CGImage, part: CGRect? = nil, into rect: CGRect? = nil, size: Int = 256) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let piece = part.flatMap { image.cropping(to: $0) } ?? image
        context.draw(piece, in: rect ?? CGRect(x: 0, y: 0, width: size, height: size))
        // The edit: one object changed.
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.8, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 110, y: 110, width: 20, height: 20))
        return context.makeImage()!
    }

    static func jpeg(_ image: CGImage) -> Data {
        GreenerImageFit.jpeg(image)!
    }

    @Test(arguments: [GreenerImageFit.Mapping.stretched, .cropped, .padded])
    func findsHowTheEditCoversThePhoto(_ mapping: GreenerImageFit.Mapping) throws {
        let photo = Self.photo()
        let edit: CGImage = switch mapping {
        case .stretched: Self.square(photo)
        case .cropped: Self.square(photo, part: CGRect(x: 0, y: 50, width: 300, height: 300))
        case .padded: Self.square(photo, into: CGRect(x: 32, y: 0, width: 192, height: 256))
        }
        #expect(GreenerImageFit.bestMapping(before: photo, after: edit) == mapping)

        let fitted = try #require(GreenerImageFit.fitted(Self.jpeg(edit), to: Self.jpeg(photo)))
        let image = try #require(GreenerImageFit.image(fitted))
        #expect(image.width == 300 && image.height == 400, "the photo's own frame")
        #expect(GreenerImageFit.difference(photo, image, .stretched) < 12, "lines up with the photo")
    }

    @Test func aSameShapeEditIsOnlyScaled() throws {
        let photo = Self.photo(width: 400, height: 300)
        let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(photo, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        let edit = try #require(context.makeImage())
        #expect(GreenerImageFit.bestMapping(before: photo, after: edit) == .stretched)
        let data = try #require(GreenerImageFit.fitted(Self.jpeg(edit), to: Self.jpeg(photo)))
        let fitted = try #require(GreenerImageFit.image(data))
        #expect(fitted.width == 400 && fitted.height == 300)
    }

    @Test func unreadableImagesGiveNothing() {
        #expect(GreenerImageFit.fitted(Data([1, 2, 3]), to: Self.jpeg(Self.photo())) == nil)
    }
}
