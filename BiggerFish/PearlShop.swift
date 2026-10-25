import FishKit
import SpriteKit
import UIKit

/// Something the Open Water's pearls buy for your fish (the shop's list is `GameTuning.pearlShop`): a body color, a
/// pattern, a hat, or a trail. Looks only, never part of what eats or is eaten (that's the fish's radius): colors and
/// patterns stay inside your body, and a hat stands at most `GameTuning.pearlHatHeadroom` above your back fin.
struct PearlItem: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case color, pattern, hat, trail

        var title: String {
            switch self {
            case .color: "Colors"
            case .pattern: "Patterns"
            case .hat: "Hats"
            case .trail: "Trails"
            }
        }
    }

    /// Saved with what a player owns and wears: never rename one.
    let id: String
    let kind: Kind
    let name: String
    let price: Int

    init(_ id: String, _ kind: Kind, _ name: String, price: Int) {
        self.id = id
        self.kind = kind
        self.name = name
        self.price = price
    }

    static func item(_ id: String) -> PearlItem? { GameTuning.pearlShop.first { $0.id == id } }
}

/// What your fish wears: one item of each kind at most, or none (the plain orange fish).
struct PlayerLook: Equatable {
    private(set) var items: [PearlItem.Kind: PearlItem] = [:]

    static let plain = PlayerLook()

    init() {}

    /// From the save (`ArcadeSave.wornLook`): an item each kind, by ID. One this version doesn't know (from a later
    /// version) or filed under the wrong kind is left off.
    init(ids: [String: String]) {
        for (kind, id) in ids {
            guard let kind = PearlItem.Kind(rawValue: kind), let item = PearlItem.item(id), item.kind == kind else { continue }
            items[kind] = item
        }
    }

    var ids: [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.key.rawValue, $0.value.id) }) }

    subscript(kind: PearlItem.Kind) -> PearlItem? { items[kind] }

    /// This look with `item` on in its kind's place.
    func wearing(_ item: PearlItem) -> PlayerLook {
        var look = self
        look.items[item.kind] = item
        return look
    }

    /// This look with nothing of `kind` on.
    func without(_ kind: PearlItem.Kind) -> PlayerLook {
        var look = self
        look.items[kind] = nil
        return look
    }

    /// The fish's colors and built-in pattern (FishKit's spots and stripes).
    var style: FishStyle {
        var style = FishStyle.player
        if let color = self[.color], let colors = PearlShopArt.colors[color.id] {
            style.body = colors.body
            style.accent = colors.accent
        }
        switch self[.pattern]?.id {
        case "pattern.spots": style.pattern = .spots
        case "pattern.stripes": style.pattern = .stripes
        default: break
        }
        return style
    }

    /// A fish drawn in this look (its style, markings and hat). Its trail is the scene's to draw (`PearlTrailMotes`).
    func fish(tailPhase: CGFloat = 0) -> FishNode {
        let node = FishNode(style: style, isPlayer: true, tailPhase: tailPhase)
        dress(node)
        return node
    }

    /// Puts this look's markings and hat on a fish drawn in its `style`.
    func dress(_ node: FishNode) {
        node.setMarkings(self[.pattern].flatMap(PearlShopArt.markings))
        node.setHeadwear(self[.hat].flatMap(PearlShopArt.hat))
    }

    var trail: PearlTrail? { self[.trail].flatMap { PearlTrail(rawValue: $0.id) } }
}

/// What a trail leaves behind you as you swim.
enum PearlTrail: String {
    case bubbles = "trail.bubbles", sparkles = "trail.sparkles", rainbow = "trail.rainbow"
}

/// The drawing of everything the shop sells, at FishKit's reference radius (30) facing right.
enum PearlShopArt {
    private static let R = FishNode.referenceRadius

    /// A pearl beside a count (the Open Water's at the top of the screen, and its card's Shop button): white, with a
    /// pale rim and a glint.
    static func pearlIcon(radius: CGFloat) -> SKNode {
        let pearl = SKShapeNode(circleOfRadius: radius)
        pearl.fillColor = SKColor(red: 0.97, green: 0.95, blue: 0.93, alpha: 1)
        pearl.strokeColor = SKColor(red: 0.85, green: 0.78, blue: 0.86, alpha: 1)
        pearl.lineWidth = 1.5
        let shine = SKShapeNode(circleOfRadius: radius * 2 / 7)
        shine.fillColor = .white
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -radius * 2.5 / 7, y: radius * 2.5 / 7)
        shine.zPosition = 1
        pearl.addChild(shine)
        return pearl
    }

    /// Each body color: the body, and the fins and tail. None is another fish's (FishKit's palette), so you can still
    /// find yourself.
    static let colors: [String: (body: SKColor, accent: SKColor)] = [
        "color.gold": (SKColor(red: 1.00, green: 0.80, blue: 0.18, alpha: 1), SKColor(red: 1.00, green: 0.93, blue: 0.55, alpha: 1)),
        "color.ruby": (SKColor(red: 0.88, green: 0.16, blue: 0.26, alpha: 1), SKColor(red: 1.00, green: 0.55, blue: 0.52, alpha: 1)),
        "color.copper": (SKColor(red: 0.78, green: 0.40, blue: 0.17, alpha: 1), SKColor(red: 0.98, green: 0.70, blue: 0.42, alpha: 1)),
        "color.pearl": (SKColor(red: 0.95, green: 0.92, blue: 0.97, alpha: 1), SKColor(red: 0.98, green: 0.74, blue: 0.87, alpha: 1)),
    ]

    // MARK: Patterns

    /// Markings for the patterns FishKit doesn't draw itself (`FishNode.setMarkings`).
    static func markings(_ item: PearlItem) -> SKNode? {
        switch item.id {
        case "pattern.bands": clownBands()
        case "pattern.stars": stars()
        default: nil
        }
    }

    /// The body's half-height at `x` (reference radius), a little inside its white outline.
    private static func halfHeight(at x: CGFloat) -> CGFloat {
        let a = FishNode.bodySize.width / 2, b = FishNode.bodySize.height / 2
        return max(0, b * sqrt(max(0, 1 - pow(x / a, 2))) - 2.2)
    }

    /// A clownfish's two white bands, edged in black.
    private static func clownBands() -> SKNode {
        let node = SKNode()
        for (center, width) in [(0.38 * R, 0.3 * R), (-0.5 * R, 0.34 * R)] {
            let left = center - width / 2, right = center + width / 2
            let path = CGMutablePath()
            let steps = 8
            for i in 0...steps {
                let x = left + (right - left) * CGFloat(i) / CGFloat(steps)
                let point = CGPoint(x: x, y: halfHeight(at: x))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            for i in (0...steps).reversed() {
                let x = left + (right - left) * CGFloat(i) / CGFloat(steps)
                path.addLine(to: CGPoint(x: x, y: -halfHeight(at: x)))
            }
            path.closeSubpath()
            let band = SKShapeNode(path: path)
            band.fillColor = .white
            band.strokeColor = .clear
            node.addChild(band)
            for x in [left, right] {
                let edge = CGMutablePath()
                edge.move(to: CGPoint(x: x, y: halfHeight(at: x)))
                edge.addLine(to: CGPoint(x: x, y: -halfHeight(at: x)))
                let line = SKShapeNode(path: edge)
                line.strokeColor = SKColor(white: 0.08, alpha: 0.85)
                line.lineWidth = 2
                line.zPosition = 0.1
                node.addChild(line)
            }
        }
        return node
    }

    /// Little white stars scattered over the body.
    private static func stars() -> SKNode {
        let node = SKNode()
        let spots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
            (-0.72, 0.18, 0.15), (-0.32, 0.5, 0.11), (-0.2, -0.12, 0.14), (0.2, 0.42, 0.1), (0.22, -0.42, 0.11),
            (-0.7, -0.38, 0.1),
        ]
        for (i, spot) in spots.enumerated() {
            let star = SKShapeNode(path: starPath(points: 5, outer: spot.r * R, inner: spot.r * R * 0.45))
            star.position = CGPoint(x: spot.x * R, y: spot.y * R)
            star.zRotation = CGFloat(i) * 0.5
            star.fillColor = SKColor(red: 1, green: 0.98, blue: 0.86, alpha: 0.95)
            star.strokeColor = .clear
            node.addChild(star)
        }
        return node
    }

    static func starPath(points: Int, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(points) + .pi / 2
            let r = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Hats

    /// A hat for `FishNode.setHeadwear`. It's drawn around the headwear's spot (just above the body, ahead of the back
    /// fin) and sits down onto the body from there. It may stand up to `GameTuning.pearlHatHeadroom` above the fin's top
    /// (`PearlShopTests.nothingMakesYouLookBigger`): it's only drawn, never part of what eats or is eaten (that's the
    /// fish's radius).
    static func hat(_ item: PearlItem) -> SKNode? {
        let hat: SKNode
        switch item.id {
        case "hat.beanie": hat = beanie()
        case "hat.flower": hat = flower()
        case "hat.sailor": hat = sailorCap()
        case "hat.cone": hat = trafficCone()
        case "hat.crown": hat = crown()
        default: return nil
        }
        // Down onto the body (its top is about this far below the headwear's spot).
        hat.position = CGPoint(x: 0, y: -0.2 * R)
        let worn = SKNode()
        worn.addChild(hat)
        return worn
    }

    private static func shape(_ path: CGPath, fill: SKColor, stroke: SKColor = SKColor(white: 0.1, alpha: 0.7),
                              line: CGFloat = 1.5, z: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = line
        node.zPosition = z
        return node
    }

    private static func ball(_ radius: CGFloat, at center: CGPoint, fill: SKColor, z: CGFloat) -> SKShapeNode {
        shape(CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
                     transform: nil), fill: fill, line: 1.2, z: z)
    }

    private static func beanie() -> SKNode {
        let node = SKNode()
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: -9.5, y: 0))
        dome.addQuadCurve(to: CGPoint(x: 9.5, y: 0), control: CGPoint(x: 0, y: 20))
        dome.closeSubpath()
        node.addChild(shape(dome, fill: SKColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1), z: 0))
        let cuff = CGPath(roundedRect: CGRect(x: -10.5, y: -2.5, width: 21, height: 4.5), cornerWidth: 2, cornerHeight: 2, transform: nil)
        node.addChild(shape(cuff, fill: SKColor(red: 0.85, green: 0.93, blue: 1, alpha: 1), z: 0.1))
        node.addChild(ball(3, at: CGPoint(x: 0, y: 11.5), fill: SKColor(red: 0.85, green: 0.93, blue: 1, alpha: 1), z: 0.2))
        return node
    }

    private static func flower() -> SKNode {
        let node = SKNode()
        let middle = CGPoint(x: 0, y: 6)
        for i in 0..<5 {
            let angle = CGFloat(i) * 2 * .pi / 5 + .pi / 2
            let petal = SKShapeNode(circleOfRadius: 3.8)
            petal.position = CGPoint(x: middle.x + cos(angle) * 4.4, y: middle.y + sin(angle) * 4.4)
            petal.fillColor = SKColor(red: 1, green: 0.55, blue: 0.75, alpha: 1)
            petal.strokeColor = SKColor(red: 0.75, green: 0.25, blue: 0.45, alpha: 0.8)
            petal.lineWidth = 1
            petal.zPosition = CGFloat(i) * 0.01
            node.addChild(petal)
        }
        let center = SKShapeNode(circleOfRadius: 2.8)
        center.position = middle
        center.fillColor = SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)
        center.strokeColor = .clear
        center.zPosition = 0.1
        node.addChild(center)
        return node
    }

    private static func sailorCap() -> SKNode {
        let node = SKNode()
        let top = CGPath(ellipseIn: CGRect(x: -11, y: 6, width: 22, height: 7), transform: nil)
        node.addChild(shape(top, fill: .white, z: 0))
        let crown = CGPath(roundedRect: CGRect(x: -8, y: -1.5, width: 16, height: 10), cornerWidth: 2, cornerHeight: 2, transform: nil)
        node.addChild(shape(crown, fill: .white, z: 0.1))
        let band = CGPath(rect: CGRect(x: -8, y: -1.5, width: 16, height: 3.2), transform: nil)
        node.addChild(shape(band, fill: SKColor(red: 0.1, green: 0.16, blue: 0.4, alpha: 1), line: 1, z: 0.2))
        let brim = CGMutablePath()
        brim.move(to: CGPoint(x: 6.5, y: -1.5))
        brim.addQuadCurve(to: CGPoint(x: 14, y: -2.5), control: CGPoint(x: 10.5, y: 1.5))
        brim.addLine(to: CGPoint(x: 6.5, y: -1.5))
        node.addChild(shape(brim, fill: SKColor(white: 0.1, alpha: 1), line: 1, z: 0.3))
        return node
    }

    /// An orange cone with two white bands, on its square base.
    private static func trafficCone() -> SKNode {
        let node = SKNode()
        let base = CGPath(roundedRect: CGRect(x: -9, y: -2.5, width: 18, height: 3), cornerWidth: 1.2, cornerHeight: 1.2,
                          transform: nil)
        node.addChild(shape(base, fill: SKColor(red: 0.8, green: 0.28, blue: 0.04, alpha: 1), z: 0))
        // The cone's half-width at a height.
        let height: CGFloat = 19
        let half = { (y: CGFloat) in 6.5 - 5.2 * y / height }
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: -half(0), y: 0))
        cone.addLine(to: CGPoint(x: -half(height), y: height))
        cone.addQuadCurve(to: CGPoint(x: half(height), y: height), control: CGPoint(x: 0, y: height + 0.8))
        cone.addLine(to: CGPoint(x: half(0), y: 0))
        cone.closeSubpath()
        node.addChild(shape(cone, fill: SKColor(red: 1, green: 0.42, blue: 0.05, alpha: 1), z: 0.1))
        for (index, (low, high)) in [(CGFloat(4.5), CGFloat(7.5)), (11, 13.8)].enumerated() {
            let band = CGMutablePath()
            band.move(to: CGPoint(x: -half(low), y: low))
            band.addLine(to: CGPoint(x: -half(high), y: high))
            band.addLine(to: CGPoint(x: half(high), y: high))
            band.addLine(to: CGPoint(x: half(low), y: low))
            band.closeSubpath()
            node.addChild(shape(band, fill: .white, stroke: .clear, line: 0, z: 0.2 + CGFloat(index) * 0.01))
        }
        return node
    }

    private static func crown() -> SKNode {
        let node = SKNode()
        let gold = SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -9, y: -2))
        path.addLine(to: CGPoint(x: -9, y: 10))
        path.addLine(to: CGPoint(x: -4.5, y: 4.5))
        path.addLine(to: CGPoint(x: 0, y: 13))
        path.addLine(to: CGPoint(x: 4.5, y: 4.5))
        path.addLine(to: CGPoint(x: 9, y: 10))
        path.addLine(to: CGPoint(x: 9, y: -2))
        path.closeSubpath()
        node.addChild(shape(path, fill: gold, stroke: SKColor(red: 0.6, green: 0.4, blue: 0.05, alpha: 1), line: 1.2, z: 0))
        for (index, tip) in [CGPoint(x: -9, y: 10), CGPoint(x: 0, y: 13), CGPoint(x: 9, y: 10)].enumerated() {
            node.addChild(ball(1.5, at: tip, fill: gold, z: 0.1 + CGFloat(index) * 0.01))
        }
        let jewel = SKShapeNode(circleOfRadius: 2)
        jewel.position = CGPoint(x: 0, y: 2)
        jewel.fillColor = SKColor(red: 0.9, green: 0.15, blue: 0.3, alpha: 1)
        jewel.strokeColor = .clear
        jewel.zPosition = 0.2
        node.addChild(jewel)
        return node
    }

    // MARK: Trails

    /// A trail's mote: its texture, how it's blended, and its size against your radius.
    static func mote(_ trail: PearlTrail) -> (texture: SKTexture, additive: Bool, size: CGFloat) {
        switch trail {
        case .bubbles: (bubbleTexture, false, 0.42)
        case .sparkles: (sparkleTexture, true, 0.62)
        case .rainbow: (ArcadeArt.glow, true, 0.7)
        }
    }

    private static let bubbleTexture: SKTexture = {
        let side: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(white: 1, alpha: 0.2).cgColor)
            cg.fillEllipse(in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.9).cgColor)
            cg.setLineWidth(3)
            cg.strokeEllipse(in: CGRect(x: 2.5, y: 2.5, width: side - 5, height: side - 5))
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: side * 0.24, y: side * 0.2, width: side * 0.24, height: side * 0.24))
        }
        return SKTexture(image: image)
    }()

    private static let sparkleTexture: SKTexture = {
        let side: CGFloat = 32
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.translateBy(x: side / 2, y: side / 2)
            cg.addPath(starPath(points: 4, outer: side / 2 - 1, inner: side * 0.11))
            cg.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).cgColor)
            cg.fillPath()
        }
        return SKTexture(image: image)
    }()
}

/// The motes a trail leaves (`PearlTrail`): each let go behind your tail where you were and left in the water as you
/// swim on, rising or twinkling as it fades. Nothing here touches the game: no random numbers, only the clock.
final class PearlTrailMotes {
    private struct Mote {
        let node: SKSpriteNode
        let at: CGPoint
        let born: CGFloat
        let index: Int
    }
    private var motes: [Mote] = []
    private var next: CGFloat = 0
    private var count = 0

    /// Lets out a mote, if one's due, behind a fish at `position` (in the water's coordinates) with `radius`, facing
    /// `facing`.
    func release(_ trail: PearlTrail, position: CGPoint, radius: CGFloat, facing: CGFloat, time: CGFloat,
                 into parent: SKNode, z: CGFloat) {
        guard time >= next else { return }
        next = time + GameTuning.pearlTrailEvery[trail]!
        count += 1
        let look = PearlShopArt.mote(trail)
        let node = SKSpriteNode(texture: look.texture)
        let side = look.size * radius
        node.size = CGSize(width: side, height: side)
        if look.additive { node.blendMode = .add }
        if trail == .rainbow {
            node.color = SKColor(hue: (CGFloat(count) * 0.045).truncatingRemainder(dividingBy: 1), saturation: 0.85,
                                 brightness: 1, alpha: 1)
            node.colorBlendFactor = 1
        }
        // A hair apart each, so two can't swap places as they're drawn.
        node.zPosition = z + CGFloat(count % 50) * 0.0001
        node.alpha = 0
        parent.addChild(node)
        let behind: CGFloat = facing < 0 ? 1.55 : -1.55
        let wobble = sin(CGFloat(count) * 2.39996) * 0.28
        motes.append(Mote(node: node, at: CGPoint(x: position.x + behind * radius, y: position.y + wobble * radius),
                          born: time, index: count))
    }

    /// Every mote where it was let go (`place` turns the water's coordinates into the scene's), at `scale` (the
    /// camera's zoom), as old as it is.
    func render(_ trail: PearlTrail?, time: CGFloat, scale: CGFloat, place: (CGPoint) -> CGPoint) {
        guard !motes.isEmpty else { return }
        let life = GameTuning.pearlTrailSeconds
        motes.removeAll { mote in
            let age = time - mote.born
            guard age < life, let trail else {
                mote.node.removeFromParent()
                return true
            }
            let t = age / life
            var point = place(mote.at)
            var size: CGFloat = 1
            switch trail {
            case .bubbles:
                point.x += sin(age * 9 + CGFloat(mote.index)) * 1.5
                point.y += age * 26
                size = 0.8 + 0.4 * t
            case .sparkles:
                size = (1 - t) * (0.75 + 0.25 * sin(age * 30 + CGFloat(mote.index)))
                mote.node.zRotation = CGFloat(mote.index) * 0.7 + age * 2
            case .rainbow:
                size = 1 - 0.6 * t
            }
            mote.node.position = point
            mote.node.setScale(scale * size)
            mote.node.alpha = min(1, age / 0.06) * (1 - t)
            return false
        }
    }

    func removeAll() {
        for mote in motes { mote.node.removeFromParent() }
        motes.removeAll()
        next = 0
    }
}
