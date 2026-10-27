import FishKit
import Foundation
import ImageIO
import SpriteKit
import Testing
import UIKit
@testable import BiggerFish

/// The app icon, the world map icons, and the home screen's two ways to play are drawn from the game's own fish and
/// jellyfish art. This redraws them into `BiggerFish/Assets.xcassets` when build/arcade-development/iconography.request
/// exists.
@MainActor struct IconographyTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let assets = root.appendingPathComponent("BiggerFish/Assets.xcassets")

    @Test func shippedIconographyExists() {
        for name in ["WorldShallowReef", "WorldJellyBloom", "WorldKelpForest", "WorldMidnightZone", "WorldSunsetCove", "LaunchArt",
                     "ModeAdventure", "ModeOpenWater"] { #expect(UIImage(named: name) != nil, "\(name) is missing") }
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
        try write(worldIcon(midnightZone()), to: "WorldMidnightZone.imageset/WorldMidnightZone.png", opaque: false)
        try write(launchChase(), to: "LaunchArt.imageset/LaunchArt.png", opaque: false)
        try write(worldIcon(sunsetCove()), to: "WorldSunsetCove.imageset/WorldSunsetCove.png", opaque: false)
        try writeModeIcons()
    }

    /// The home screen's two pictures alone, when build/arcade-development/mode-icons.request exists.
    @Test func manualRenderModeIcons() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/mode-icons.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        try writeModeIcons()
        try FileManager.default.removeItem(at: marker)
    }

    private func writeModeIcons() throws {
        try write(worldIcon(adventure()), to: "ModeAdventure.imageset/ModeAdventure.png", opaque: false)
        try write(worldIcon(openWater()), to: "ModeOpenWater.imageset/ModeOpenWater.png", opaque: false)
    }

    /// Sunset Cove's picture alone (the prototype's), when build/arcade-development/sunset-icon.request exists.
    @Test func manualRenderSunsetCoveIcon() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/sunset-icon.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        try write(worldIcon(sunsetCove()), to: "WorldSunsetCove.imageset/WorldSunsetCove.png", opaque: false)
        try FileManager.default.removeItem(at: marker)
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

    /// A striped reef fish and the player's little orange fish over coral, swimming apart: the orange fish heads
    /// up and away to the right, the way it swims in the game.
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
        reef.addChild(fish(Self.teal, player: false, radius: 70, at: CGPoint(x: -38, y: 22), tilt: 0.1, facing: -1))
        reef.addChild(fish(.player, player: true, radius: 34, at: CGPoint(x: 100, y: 118), tilt: 0.32))
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

    /// The player's fish in a pool of dark water, carrying an anglerfish lure like the game's: a thin stalk from its
    /// forehead to a small cyan-green light glowing in front of its face.
    private func midnightZone() -> SKNode {
        let zone = SKNode()
        let side = Self.tile, radius: CGFloat = 46
        let dark = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let colors = [SKColor(red: 0.02, green: 0.04, blue: 0.12, alpha: 0.95).cgColor,
                          SKColor(red: 0.03, green: 0.06, blue: 0.16, alpha: 0.85).cgColor,
                          SKColor(red: 0.03, green: 0.06, blue: 0.16, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.72, 1])!
            let center = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                                 endRadius: side * 0.48, options: [])
        }
        let water = SKSpriteNode(texture: SKTexture(image: dark))
        water.zPosition = -5
        zone.addChild(water)
        let body = CGPoint(x: -22, y: -22)
        zone.addChild(fish(.player, player: true, radius: radius, at: body, tilt: 0.08))
        // The lure, at the game's proportions (`GameScene.anglerLure`): from the forehead up and ahead of the face.
        let scale = radius / FishNode.referenceRadius, r = FishNode.referenceRadius
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.x + x * r * scale, y: body.y + y * r * scale) }
        let tip = point(1.4, 1.25)
        let stalkPath = CGMutablePath()
        stalkPath.move(to: point(0.75, 0.72))
        stalkPath.addQuadCurve(to: tip, control: point(1.0, 1.6))
        let stalk = SKShapeNode(path: stalkPath)
        stalk.strokeColor = SKColor(red: 1, green: 0.84, blue: 0.4, alpha: 1)
        stalk.lineWidth = 3.5
        stalk.lineCap = .round
        stalk.zPosition = 11
        zone.addChild(stalk)
        let glow = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            let colors = [GameTuning.lureColor.cgColor, GameTuning.lureColor.withAlphaComponent(0.35).cgColor,
                          GameTuning.lureColor.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1])!
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                                 endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
        let halo = SKSpriteNode(texture: SKTexture(image: glow), size: CGSize(width: 78, height: 78))
        halo.position = tip
        halo.zPosition = 12
        zone.addChild(halo)
        let core = SKShapeNode(circleOfRadius: 7)
        core.fillColor = .white
        core.strokeColor = GameTuning.lureColor
        core.lineWidth = 2
        core.position = tip
        core.zPosition = 13
        zone.addChild(core)
        return zone
    }

    /// A pool of sunset water, coral at the top to deep purple, with the low sun glowing at its surface and a boat's
    /// hull there; its line hangs down to a hook baited with a little pink fish, and the player's fish eyes it.
    private func sunsetCove() -> SKNode {
        let cove = SKNode()
        let side = Self.tile
        let water = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.addEllipse(in: CGRect(x: side * 0.03, y: side * 0.03, width: side * 0.94, height: side * 0.94))
            cg.clip()
            let colors = [ArcadeArt.sunsetWaterColors.top.cgColor, ArcadeArt.sunsetWaterColors.middle.cgColor,
                          ArcadeArt.sunsetWaterColors.bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.25, 0.65, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            // The low sun at the surface, and its light slanting down.
            let sun = CGPoint(x: side * 0.7, y: side * 0.19)
            let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.white.cgColor, UIColor(red: 1, green: 0.88, blue: 0.6, alpha: 0.85).cgColor,
                         UIColor(red: 1, green: 0.7, blue: 0.5, alpha: 0).cgColor] as CFArray, locations: [0, 0.18, 1])!
            cg.drawRadialGradient(glow, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: side * 0.5, options: [])
            cg.setFillColor(UIColor(white: 1, alpha: 0.08).cgColor)
            for i in 0..<3 {
                let x = side * (0.42 + CGFloat(i) * 0.14)
                cg.move(to: CGPoint(x: x, y: side * 0.2)); cg.addLine(to: CGPoint(x: x + side * 0.06, y: side * 0.2))
                cg.addLine(to: CGPoint(x: x - side * 0.2, y: side)); cg.addLine(to: CGPoint(x: x - side * 0.34, y: side))
                cg.closePath(); cg.fillPath()
            }
        }
        let pool = SKSpriteNode(texture: SKTexture(image: water))
        pool.zPosition = -5
        cove.addChild(pool)
        // The boat at the surface, its line down to the baited hook.
        let surface: CGFloat = side * 0.3, rod = CGPoint(x: 52, y: surface)
        let boat = HookBoatNode(seed: 3)
        boat.setScale(1.1)
        boat.position = rod
        boat.zPosition = -1
        cove.addChild(boat)
        let hook = CGPoint(x: 52, y: -6), bait: CGFloat = 20
        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: rod.x, y: rod.y + 5))
        linePath.addLine(to: CGPoint(x: hook.x, y: hook.y + HookMetal.eye * bait))
        let line = SKShapeNode(path: linePath)
        line.strokeColor = .white
        line.lineWidth = 2.5
        line.zPosition = -2
        cove.addChild(line)
        let metal = HookMetal.make()
        metal.position = hook
        metal.setScale(bait / FishNode.referenceRadius)
        metal.lineWidth = 3.5 / (bait / FishNode.referenceRadius)
        metal.zPosition = -1.5
        cove.addChild(metal)
        cove.addChild(fish(Self.pink, player: false, radius: bait, at: hook, tilt: 0.12, facing: -1))
        cove.addChild(fish(.player, player: true, radius: 38, at: CGPoint(x: -62, y: -70), tilt: 0.28, facing: 1))
        return cove
    }

    /// Adventure: a treasure map, its dotted trail winding from the player's little orange fish past a stop in each
    /// world's color, in the map's order, to a gold crown.
    private func adventure() -> SKNode {
        let map = SKNode()
        let side = Self.tile
        let ink = UIColor(red: 0.52, green: 0.32, blue: 0.15, alpha: 1)
        let parchment = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            let disc = CGRect(x: side * 0.03, y: side * 0.03, width: side * 0.94, height: side * 0.94)
            cg.saveGState()
            cg.addEllipse(in: disc)
            cg.clip()
            let paper = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1).cgColor,
                         UIColor(red: 0.93, green: 0.79, blue: 0.56, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            cg.drawRadialGradient(paper, startCenter: CGPoint(x: side / 2, y: side * 0.44), startRadius: 0,
                                  endCenter: CGPoint(x: side / 2, y: side / 2), endRadius: side * 0.5, options: [.drawsAfterEndLocation])
            // A few faint stains, as an old map has.
            cg.setFillColor(ink.withAlphaComponent(0.07).cgColor)
            for (x, y, r) in [(0.72, 0.3, 0.13), (0.25, 0.68, 0.1), (0.62, 0.78, 0.07)] {
                cg.fillEllipse(in: CGRect(x: side * (x - r), y: side * (y - r), width: side * r * 2, height: side * r * 2))
            }
            cg.restoreGState()
            cg.setStrokeColor(ink.withAlphaComponent(0.85).cgColor)
            cg.setLineWidth(6)
            cg.strokeEllipse(in: disc.insetBy(dx: 3, dy: 3))
        }
        let paper = SKSpriteNode(texture: SKTexture(image: parchment))
        paper.zPosition = -5
        map.addChild(paper)
        // The fish at the trail's start, a stop for each world, the crown at its end: all of it centered on the map and
        // inside its rim, the fish level.
        let route = [CGPoint(x: -62, y: -66), CGPoint(x: -2, y: -86), CGPoint(x: 58, y: -60), CGPoint(x: 28, y: -12),
                     CGPoint(x: -32, y: 12), CGPoint(x: -12, y: 64), CGPoint(x: 50, y: 66)]
        for dot in dots(along: route, spacing: 15) {
            let node = SKShapeNode(circleOfRadius: 4)
            node.fillColor = ink.withAlphaComponent(0.8)
            node.strokeColor = .clear
            node.position = dot
            node.zPosition = -2
            map.addChild(node)
        }
        for (world, center) in zip(ArcadeWorld.campaign, route.dropFirst()) {
            let stop = SKShapeNode(circleOfRadius: 16)
            stop.fillColor = world.mapColor
            stop.strokeColor = .white
            stop.lineWidth = 4.5
            stop.position = center
            map.addChild(stop)
        }
        let crown = SKSpriteNode(texture: SKTexture(image: symbol("crown.fill", size: 56, color: UIColor(DeepEndColors.gold),
                                                                  outline: ink)))
        crown.position = CGPoint(x: route[route.count - 1].x, y: route[route.count - 1].y + 6)
        crown.zPosition = 2
        map.addChild(crown)
        map.addChild(fish(.player, player: true, radius: 28, at: route[0]))
        return map
    }

    /// The Open Water: a pool of open sea, sunlit from above, and the player's little orange fish following a trail of
    /// pearls (the mode's own, in their Shallow Reef look) up and away.
    private func openWater() -> SKNode {
        let sea = SKNode()
        let side = Self.tile
        let water = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.addEllipse(in: CGRect(x: side * 0.03, y: side * 0.03, width: side * 0.94, height: side * 0.94))
            cg.clip()
            let depth = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(red: 0.38, green: 0.8, blue: 0.95, alpha: 1).cgColor,
                         UIColor(red: 0.1, green: 0.42, blue: 0.75, alpha: 1).cgColor,
                         UIColor(red: 0.03, green: 0.12, blue: 0.36, alpha: 1).cgColor] as CFArray, locations: [0, 0.45, 1])!
            cg.drawLinearGradient(depth, start: .zero, end: CGPoint(x: 0, y: side), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            // Sunlight slanting down from the surface.
            cg.setFillColor(UIColor(white: 1, alpha: 0.08).cgColor)
            for i in 0..<4 {
                let x = side * (0.08 + CGFloat(i) * 0.24)
                cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x + side * 0.1, y: 0))
                cg.addLine(to: CGPoint(x: x + side * 0.3, y: side)); cg.addLine(to: CGPoint(x: x + side * 0.12, y: side))
                cg.closePath(); cg.fillPath()
            }
        }
        let pool = SKSpriteNode(texture: SKTexture(image: water))
        pool.zPosition = -5
        sea.addChild(pool)
        let look = GameTuning.openWaterPearlLook(.shallowReef)
        for (index, at) in [CGPoint(x: 16, y: -6), CGPoint(x: 58, y: 24), CGPoint(x: 92, y: 62)].enumerated() {
            let pearl = SKNode()
            pearl.position = at
            let glow = SKSpriteNode(texture: ArcadeArt.glow, size: CGSize(width: 60, height: 60))
            glow.color = look.fill
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0.55
            let radius: CGFloat = 14 - CGFloat(index)
            let ball = SKShapeNode(circleOfRadius: radius)
            ball.fillColor = look.fill
            ball.strokeColor = look.rim
            ball.lineWidth = 3
            ball.zPosition = 0.1
            let shine = SKShapeNode(circleOfRadius: radius * 0.32)
            shine.fillColor = .white
            shine.strokeColor = .clear
            shine.position = CGPoint(x: -radius * 0.35, y: radius * 0.35)
            shine.zPosition = 0.2
            for part in [glow, ball, shine] as [SKNode] { pearl.addChild(part) }
            sea.addChild(pearl)
        }
        for (x, y, r) in [(-104.0, 6.0, 7.0), (-96.0, 34.0, 5.0), (-108.0, 58.0, 8.0)] {
            let bubble = SKShapeNode(circleOfRadius: r)
            bubble.strokeColor = SKColor(white: 1, alpha: 0.55)
            bubble.fillColor = SKColor(white: 1, alpha: 0.12)
            bubble.lineWidth = 2.5
            bubble.position = CGPoint(x: x, y: y)
            sea.addChild(bubble)
        }
        sea.addChild(fish(.player, player: true, radius: 42, at: CGPoint(x: -46, y: -46), mouth: 0.55, tilt: 0.3))
        return sea
    }

    /// Points `spacing` apart along a smooth curve through `points` (Catmull-Rom).
    private func dots(along points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        var samples: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            for step in 0..<40 {
                let t = CGFloat(step) / 40, t2 = t * t, t3 = t2 * t
                func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
                }
                samples.append(CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        samples.append(points[points.count - 1])
        var result: [CGPoint] = [], travelled = spacing
        for (a, b) in zip(samples, samples.dropFirst()) {
            travelled += hypot(b.x - a.x, b.y - a.y)
            if travelled >= spacing { result.append(b); travelled = 0 }
        }
        return result
    }

    /// An SF Symbol drawn in `color`, ringed in `outline`.
    private func symbol(_ name: String, size: CGFloat, color: UIColor, outline: UIColor) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .bold)
        let base = UIImage(systemName: name, withConfiguration: config)!
        let pad: CGFloat = 4
        return UIGraphicsImageRenderer(size: CGSize(width: base.size.width + pad * 2, height: base.size.height + pad * 2)).image { _ in
            let ring = base.withTintColor(outline, renderingMode: .alwaysOriginal)
            for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 8) {
                ring.draw(at: CGPoint(x: pad + cos(angle) * 3, y: pad + sin(angle) * 3))
            }
            base.withTintColor(color, renderingMode: .alwaysOriginal).draw(at: CGPoint(x: pad, y: pad))
        }
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
