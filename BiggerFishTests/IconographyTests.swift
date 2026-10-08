import FishKit
import Foundation
import ImageIO
import SpriteKit
import Testing
import UIKit
@testable import BiggerFish

/// The app icon and the world map icons are drawn from the game's own fish and jellyfish art. This
/// redraws them into `BiggerFish/Assets.xcassets` when build/arcade-development/iconography.request exists.
@MainActor struct IconographyTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let assets = root.appendingPathComponent("BiggerFish/Assets.xcassets")

    @Test func shippedIconographyExists() {
        for name in ["WorldShallowReef", "WorldJellyBloom", "WorldKelpForest", "LaunchArt"] { #expect(UIImage(named: name) != nil, "\(name) is missing") }
        #expect(UIColor(named: "LaunchBackground") != nil)
        let icon = Self.assets.appendingPathComponent("AppIcon.appiconset/AppIcon-1024.png")
        let image = CGImageSourceCreateWithURL(icon as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        #expect(image?.width == 1024 && image?.height == 1024)
        // The App Store rejects app icons with an alpha channel.
        #expect(image.map { [.none, .noneSkipFirst, .noneSkipLast].contains($0.alphaInfo) } == true)
    }

    @Test func manualRenderIconography() throws {
        guard FileManager.default.fileExists(atPath: Self.root
            .appendingPathComponent("build/arcade-development/iconography.request").path) else { return }
        try write(appIcon(), to: "AppIcon.appiconset/AppIcon-1024.png", opaque: true)
        try write(worldIcon(shallowReef()), to: "WorldShallowReef.imageset/WorldShallowReef.png", opaque: false)
        try write(worldIcon(jellyBloom()), to: "WorldJellyBloom.imageset/WorldJellyBloom.png", opaque: false)
        try write(worldIcon(kelpForest()), to: "WorldKelpForest.imageset/WorldKelpForest.png", opaque: false)
        try write(launchChase(), to: "LaunchArt.imageset/LaunchArt.png", opaque: false)
    }

    // MARK: Art

    private static let tile: CGFloat = 300
    private static let teal = FishStyle(body: SKColor(red: 0.18, green: 0.77, blue: 0.71, alpha: 1),
        accent: SKColor(red: 0.60, green: 0.95, blue: 0.85, alpha: 1), pattern: .stripes, tail: .fan, eyeScale: 1.1, hasDorsalFin: true)
    private static let purple = FishStyle(body: SKColor(red: 0.61, green: 0.36, blue: 0.90, alpha: 1),
        accent: SKColor(red: 0.85, green: 0.72, blue: 1.00, alpha: 1), pattern: .spots, tail: .fork, eyeScale: 1.0, hasDorsalFin: true)
    private static let pink = FishStyle(body: SKColor(red: 0.95, green: 0.36, blue: 0.71, alpha: 1),
        accent: SKColor(red: 1.00, green: 0.75, blue: 0.88, alpha: 1), pattern: .plain, tail: .point, eyeScale: 1.2, hasDorsalFin: false)

    private func fish(_ style: FishStyle, player: Bool, radius: CGFloat, at position: CGPoint, mouth: CGFloat = 0,
                      tilt: CGFloat = 0, facing: CGFloat = 1) -> FishNode {
        let node = FishNode(style: style, isPlayer: player, tailPhase: 0.6)
        node.zPosition = player ? 10 : 5
        node.position = position
        node.apply(radius: radius, facing: facing, tilt: tilt, stretchX: 1, stretchY: 1, mouthOpen: mouth, time: 0, tailRate: 0)
        return node
    }

    /// There's always a bigger fish: three fish, each about to eat the next, in deep water.
    private func appIcon() -> (SKView, SKNode, CGSize) {
        let side: CGFloat = 1024
        let scene = SKScene(size: CGSize(width: side, height: side))
        let water = UIGraphicsImageRenderer(size: scene.size).image { context in
            let cg = context.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 0.10, green: 0.62, blue: 0.70, alpha: 1).cgColor,
                         UIColor(red: 0.02, green: 0.12, blue: 0.30, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side * 0.35, y: side),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            // Light rays slanting down through the water.
            cg.setFillColor(UIColor(white: 1, alpha: 0.05).cgColor)
            for i in 0..<4 {
                let x = side * (0.15 + CGFloat(i) * 0.22)
                cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x + side * 0.12, y: 0))
                cg.addLine(to: CGPoint(x: x + side * 0.32, y: side)); cg.addLine(to: CGPoint(x: x + side * 0.1, y: side))
                cg.closePath(); cg.fillPath()
            }
        }
        let background = SKSpriteNode(texture: SKTexture(image: water))
        background.position = CGPoint(x: side / 2, y: side / 2)
        background.zPosition = -20
        scene.addChild(background)
        for (x, y, r) in [(0.12, 0.9, 20.0), (0.2, 0.82, 12.0), (0.28, 0.91, 9.0), (0.47, 0.88, 16.0), (0.54, 0.81, 9.0)] {
            let bubble = SKShapeNode(circleOfRadius: r)
            bubble.strokeColor = SKColor(white: 1, alpha: 0.5)
            bubble.fillColor = SKColor(white: 1, alpha: 0.1)
            bubble.lineWidth = 5
            bubble.position = CGPoint(x: side * x, y: side * y)
            scene.addChild(bubble)
        }
        scene.addChild(fish(Self.pink, player: false, radius: 50, at: CGPoint(x: side * 0.87, y: side * 0.77)))
        scene.addChild(fish(Self.purple, player: false, radius: 98, at: CGPoint(x: side * 0.66, y: side * 0.57), mouth: 0.8, tilt: 0.15))
        scene.addChild(fish(.player, player: true, radius: 172, at: CGPoint(x: side * 0.34, y: side * 0.31), mouth: 0.95, tilt: 0.15))
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        view.presentScene(scene)
        return (view, scene, scene.size)
    }

    /// A striped reef fish and the player's little orange fish over coral.
    private func shallowReef() -> SKNode {
        let reef = SKNode()
        let corals = [SKColor(red: 1, green: 0.45, blue: 0.55, alpha: 1), SKColor(red: 1, green: 0.66, blue: 0.3, alpha: 1),
                      SKColor(red: 0.98, green: 0.5, blue: 0.75, alpha: 1)]
        for (i, color) in corals.enumerated() {
            let x = CGFloat(i - 1) * 85, height: CGFloat = i == 1 ? 120 : 90
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: -140)); path.addLine(to: CGPoint(x: x, y: -140 + height))
            path.move(to: CGPoint(x: x, y: -140 + height * 0.45)); path.addLine(to: CGPoint(x: x + 30, y: -140 + height * 0.8))
            path.move(to: CGPoint(x: x, y: -140 + height * 0.6)); path.addLine(to: CGPoint(x: x - 26, y: -140 + height * 0.9))
            let coral = SKShapeNode(path: path)
            coral.strokeColor = color
            coral.lineWidth = 22
            coral.lineCap = .round
            reef.addChild(coral)
        }
        reef.addChild(fish(Self.teal, player: false, radius: 78, at: CGPoint(x: 10, y: 40), tilt: 0.08))
        reef.addChild(fish(.player, player: true, radius: 38, at: CGPoint(x: -95, y: 105), facing: -1))
        return reef
    }

    /// The jellyfish, with the player's fish bouncing on its dome.
    private func jellyBloom() -> SKNode {
        let bloom = SKNode()
        let jelly = JellyfishNode(radius: 95, tentacleLength: 150, phase: 1.2)
        jelly.animate(time: 0.4)
        jelly.position = CGPoint(x: 0, y: 30)
        bloom.addChild(jelly)
        bloom.addChild(fish(.player, player: true, radius: 34, at: CGPoint(x: 40, y: 140), tilt: 0.3))
        return bloom
    }

    /// The player's fish swimming between golden kelp stalks, with a smaller fish's shadow lurking behind them.
    private func kelpForest() -> SKNode {
        let forest = SKNode()
        let shadow = fish(FishStyle(body: .gray, accent: .gray, pattern: .plain, tail: .fork, eyeScale: 1, hasDorsalFin: true),
                          player: false, radius: 24, at: CGPoint(x: 92, y: -62), facing: -1)
        silhouette(shadow)
        shadow.zPosition = -2
        forest.addChild(shadow)
        forest.addChild(kelpStalk(at: -95, height: 290, lean: 14))
        forest.addChild(kelpStalk(at: 100, height: 270, lean: -18))
        forest.addChild(kelpStalk(at: 20, height: 150, lean: 8, z: -1))
        forest.addChild(fish(.player, player: true, radius: 40, at: CGPoint(x: 5, y: 40), tilt: 0.12))
        return forest
    }

    /// A giant-kelp stalk: a thick wavy stem with blades on alternate sides, each with a float, olive at the
    /// root and gold at the top.
    private func kelpStalk(at x: CGFloat, height: CGFloat, lean: CGFloat, z: CGFloat = 0) -> SKNode {
        let node = SKNode()
        node.zPosition = z
        func point(_ t: CGFloat) -> CGPoint { CGPoint(x: x + lean * t * t + sin(t * 6) * 6, y: -150 + height * t) }
        let stem = CGMutablePath()
        stem.move(to: point(0))
        for i in 1...30 { stem.addLine(to: point(CGFloat(i) / 30)) }
        let stemNode = SKShapeNode(path: stem)
        stemNode.strokeColor = SKColor(red: 0.36, green: 0.42, blue: 0.13, alpha: 1)
        stemNode.lineWidth = 9
        stemNode.lineCap = .round
        node.addChild(stemNode)
        var t: CGFloat = 0.18, side: CGFloat = 1
        while t < 0.98 {
            let base = point(t)
            let blade = SKShapeNode(ellipseOf: CGSize(width: 22, height: 62 * (1 - 0.35 * t)))
            blade.fillColor = SKColor(red: 0.42 + 0.32 * t, green: 0.55 + 0.13 * t, blue: 0.16 + 0.08 * t, alpha: 1)
            blade.strokeColor = SKColor(red: 0.3, green: 0.38, blue: 0.1, alpha: 0.8)
            blade.lineWidth = 2
            blade.zRotation = -side * 0.75
            blade.position = CGPoint(x: base.x + side * 20, y: base.y + 18)
            node.addChild(blade)
            let float = SKShapeNode(circleOfRadius: 5.5)
            float.fillColor = SKColor(red: 0.62, green: 0.6, blue: 0.2, alpha: 1)
            float.strokeColor = .clear
            float.position = base
            node.addChild(float)
            side = -side
            t += 0.16
        }
        return node
    }

    /// A fish in the kelp, as the game shows one: a single dark shape.
    private func silhouette(_ node: SKNode) {
        for child in node.children {
            if let shape = child as? SKShapeNode {
                if shape.fillColor.cgColor.alpha > 0 { shape.fillColor = GameTuning.kelpSilhouette }
                if shape.strokeColor.cgColor.alpha > 0 { shape.strokeColor = GameTuning.kelpSilhouette }
            }
            silhouette(child)
        }
    }

    private func worldIcon(_ art: SKNode) -> (SKView, SKNode, CGSize) {
        let scene = SKScene(size: CGSize(width: Self.tile, height: Self.tile))
        scene.backgroundColor = .clear
        art.position = CGPoint(x: Self.tile / 2, y: Self.tile / 2)
        scene.addChild(art)
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        view.allowsTransparency = true
        view.presentScene(scene)
        return (view, art, scene.size)
    }

    /// The loading screen's art: the icon's three fish in a line, each about to eat the next.
    private func launchChase() -> (SKView, SKNode, CGSize) {
        let art = SKNode()
        art.addChild(fish(Self.pink, player: false, radius: 27, at: CGPoint(x: 280, y: 28), tilt: 0.05))
        art.addChild(fish(Self.purple, player: false, radius: 50, at: CGPoint(x: 112, y: 12), mouth: 0.8, tilt: 0.05))
        art.addChild(fish(.player, player: true, radius: 82, at: CGPoint(x: -150, y: -10), mouth: 0.95, tilt: 0.05))
        return render(art, size: CGSize(width: 680, height: 240))
    }

    private func render(_ art: SKNode, size: CGSize) -> (SKView, SKNode, CGSize) {
        let scene = SKScene(size: size)
        scene.backgroundColor = .clear
        art.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scene.addChild(art)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.allowsTransparency = true
        view.presentScene(scene)
        return (view, art, size)
    }

    // MARK: Output

    /// Draws the node at `size` points, 1 pixel per point; `opaque` drops the alpha channel.
    private func write(_ render: (SKView, SKNode, CGSize), to path: String, opaque: Bool) throws {
        try write(render, toURL: Self.assets.appendingPathComponent(path), opaque: opaque)
    }

    private func write(_ render: (SKView, SKNode, CGSize), toURL url: URL, opaque: Bool) throws {
        let (view, node, size) = render
        let texture = try #require(view.texture(from: node))
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(texture.cgImage(), in: CGRect(origin: .zero, size: size))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
