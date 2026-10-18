import UIKit
import GreenCore
import GreenCoreFakes

/// Rendered stand-in photos for the demo scenes (spec §11), laid out from each fixture's bounding boxes so
/// hotspots land on the drawn objects, plus the matching "greener setup" picture the demo image editor returns.
nonisolated enum DemoArtwork {
    static let size = CGSize(width: 1200, height: 900)

    static func photo(for scene: DemoScene) -> Data { originals[scene] ?? Data() }

    static func greenerPhoto(for scene: DemoScene) -> Data { greener[scene] ?? Data() }

    /// The demo scene a photo was rendered from, if any.
    static func scene(matching photo: Data) -> DemoScene? {
        originals.first { $0.value == photo }?.key
    }

    private static let originals: [DemoScene: Data] = Dictionary(uniqueKeysWithValues:
        DemoScene.allCases.map { ($0, render($0, greener: false)) })

    private static let greener: [DemoScene: Data] = Dictionary(uniqueKeysWithValues:
        DemoScene.allCases.map { ($0, render($0, greener: true)) })

    // MARK: - Drawing

    private struct Look {
        var symbol: String
        var color: UIColor
        /// Replacement drawn in the greener picture; nil keeps the object and adds a badge.
        var greenerSymbol: String?
        var badge: String
    }

    private static func look(for component: IdentifiedComponent) -> Look {
        let name = component.name.lowercased()
        if name.contains("laptop") { return Look(symbol: "laptopcomputer", color: .darkGray, badge: "arrow.3.trianglepath") }
        if name.contains("monitor") { return Look(symbol: "display", color: .black, badge: "arrow.3.trianglepath") }
        if name.contains("cup") { return Look(symbol: "cup.and.saucer.fill", color: .white, greenerSymbol: "mug.fill", badge: "leaf.fill") }
        if name.contains("lamp") { return Look(symbol: "lamp.desk.fill", color: .darkGray, badge: "arrow.3.trianglepath") }
        if name.contains("burger") { return Look(symbol: "takeoutbag.and.cup.and.straw.fill", color: .brown, greenerSymbol: "carrot.fill", badge: "leaf.fill") }
        if name.contains("fries") { return Look(symbol: "frying.pan.fill", color: .orange, greenerSymbol: "leaf.fill", badge: "leaf.fill") }
        if name.contains("shake") { return Look(symbol: "waterbottle.fill", color: .brown, greenerSymbol: "takeoutbag.and.cup.and.straw.fill", badge: "leaf.fill") }
        if name.contains("bar") && !name.contains("e-bike") { return Look(symbol: "rectangle.fill", color: .orange, badge: "leaf.fill") }
        if name.contains("cola") || name.contains("can") { return Look(symbol: "cylinder.fill", color: .red, badge: "leaf.fill") }
        if name.contains("charger") { return Look(symbol: "bolt.batteryblock.fill", color: .darkGray, badge: "powerplug.fill") }
        if name.contains("e-bike") || name.contains("bike") { return Look(symbol: "bicycle", color: .black, badge: "arrow.3.trianglepath") }
        if name.contains("strip") { return Look(symbol: "poweroutlet.strip.fill", color: .white, badge: "arrow.3.trianglepath") }
        return Look(symbol: component.category.systemImage, color: .darkGray, badge: "leaf.fill")
    }

    private static func render(_ scene: DemoScene, greener: Bool) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            drawRoom(scene, in: context.cgContext)
            for component in scene.identifyResponse.components {
                draw(component, greener: greener)
            }
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }

    private static var format: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return format
    }

    private static func drawRoom(_ scene: DemoScene, in context: CGContext) {
        let wall: [UIColor] = switch scene {
        case .deskSetup: [UIColor(white: 0.88, alpha: 1), UIColor(red: 0.78, green: 0.80, blue: 0.76, alpha: 1)]
        case .meal: [UIColor(red: 0.93, green: 0.89, blue: 0.82, alpha: 1), UIColor(red: 0.85, green: 0.80, blue: 0.72, alpha: 1)]
        case .eBikeCorner: [UIColor(red: 0.80, green: 0.84, blue: 0.88, alpha: 1), UIColor(red: 0.70, green: 0.74, blue: 0.78, alpha: 1)]
        case .proteinShake: [UIColor(red: 0.90, green: 0.92, blue: 0.86, alpha: 1), UIColor(red: 0.80, green: 0.84, blue: 0.76, alpha: 1)]
        }
        let surface: UIColor = switch scene {
        case .deskSetup: UIColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1)
        case .meal: UIColor(red: 0.92, green: 0.92, blue: 0.90, alpha: 1)
        case .eBikeCorner: UIColor(red: 0.45, green: 0.45, blue: 0.47, alpha: 1)
        case .proteinShake: UIColor(red: 0.62, green: 0.50, blue: 0.38, alpha: 1)
        }
        let colors = wall.map(\.cgColor) as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        surface.setFill()
        context.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38))
    }

    private static func draw(_ component: IdentifiedComponent, greener: Bool) {
        let look = look(for: component)
        let box = component.boundingBox.clamped
        let rect = CGRect(x: box.x * size.width, y: box.y * size.height,
                          width: box.width * size.width, height: box.height * size.height).insetBy(dx: 6, dy: 6)
        let swapped = greener ? (look.greenerSymbol ?? look.symbol) : look.symbol
        let color = greener && look.greenerSymbol != nil ? UIColor(red: 0.20, green: 0.62, blue: 0.36, alpha: 1) : look.color
        drawSymbol(swapped, color: color, in: rect)
        if greener {
            let side = min(rect.width, rect.height) * 0.38
            let badge = CGRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: badge.insetBy(dx: -side * 0.12, dy: -side * 0.12)).fill()
            drawSymbol(look.badge, color: UIColor(red: 0.20, green: 0.62, blue: 0.36, alpha: 1), in: badge)
        }
    }

    private static func drawSymbol(_ name: String, color: UIColor, in rect: CGRect) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 400, weight: .regular)
            .applying(UIImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)
                ?? UIImage(systemName: "shippingbox.fill", withConfiguration: configuration) else { return }
        let scale = min(rect.width / symbol.size.width, rect.height / symbol.size.height)
        let fitted = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        symbol.draw(in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                               width: fitted.width, height: fitted.height))
    }
}

/// Demo-mode image editor: returns the pre-rendered greener picture of the scene the photo came from.
nonisolated struct DemoImageEditor: ImageEditor {
    var latency: Duration

    func editImage(_ image: Data, prompt: String) async throws -> Data {
        try await Task.sleep(for: latency)
        return DemoArtwork.greenerPhoto(for: DemoArtwork.scene(matching: image) ?? .deskSetup)
    }
}
