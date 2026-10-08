import FishKit
import SpriteKit
import UIKit

/// A bed of giant kelp drawn upward from its base at the node's origin: plants with a wavy stalk and blades
/// on alternate sides, each with a small float, shading from dark olive at the roots to sunlit gold at the top.
/// The back bed is darker and grows behind every fish; the front bed is fainter and grows in front of the
/// other fish, so fish inside show through it as silhouettes. Plants are pictures drawn once and shared,
/// so a screenful of kelp costs a few sprites a frame.
final class KelpNode: SKNode {
    private var plants: [(node: SKSpriteNode, phase: CGFloat, rate: CGFloat)] = []

    init(width: CGFloat, height: CGFloat, seed: UInt64, front: Bool) {
        super.init()
        var rng = SeededGenerator(seed: 0x6B656C70 &+ seed)
        let leafy = front && GameTuning.kelpFishLook == .leaves
        let pictures = front ? (leafy ? KelpArt.leafyFront : KelpArt.front) : KelpArt.back
        let count = max(front ? 2 : 4, Int(width / (leafy ? 30 : front ? 50 : 26)))
        for index in 0..<count {
            let x = -width / 2 + width * (CGFloat(index) + CGFloat.random(in: 0.15...0.85, using: &rng)) / CGFloat(count)
            let texture = pictures[Int.random(in: 0..<pictures.count, using: &rng)]
            let plant = SKSpriteNode(texture: texture)
            plant.anchorPoint = CGPoint(x: 0.5, y: 0)
            let tall = height * CGFloat.random(in: front ? 0.7...0.95 : 0.8...1.02, using: &rng)
            plant.size = CGSize(width: texture.size().width, height: tall)
            plant.xScale = Bool.random(using: &rng) ? 1 : -1
            plant.position = CGPoint(x: x, y: 0)
            addChild(plant)
            plants.append((plant, CGFloat.random(in: 0..<(2 * .pi), using: &rng), CGFloat.random(in: 0.7...1.1, using: &rng)))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func sway(time: CGFloat) {
        for plant in plants {
            plant.node.zRotation = 0.045 * sin(time * 0.9 * plant.rate + plant.phase)
        }
    }
}

/// Kelp plant pictures, drawn once.
private enum KelpArt {
    static let height: CGFloat = 340
    static let width: CGFloat = 150
    static let back: [SKTexture] = (0..<5).map { plant(seed: UInt64($0), dim: 0.62, alpha: 0.95) }
    static let front: [SKTexture] = (0..<4).map { plant(seed: 100 + UInt64($0), dim: 1, alpha: 0.5) }
    /// Solid, broad-bladed plants that partly hide the fish behind them.
    static let leafyFront: [SKTexture] = (0..<4).map { plant(seed: 200 + UInt64($0), dim: 0.9, alpha: 1, blades: 1.45) }

    /// Base, middle, and top colors of the blades, from dark at the roots to sunlit at the top.
    private static let shades: [(red: CGFloat, green: CGFloat, blue: CGFloat)] = [
        (0.27, 0.33, 0.1), (0.45, 0.5, 0.15), (0.66, 0.63, 0.22),
    ]

    private static func plant(seed: UInt64, dim: CGFloat, alpha: CGFloat, blades: CGFloat = 1) -> SKTexture {
        var rng = SeededGenerator(seed: 0x6B656C71 &+ seed)
        let lean = CGFloat.random(in: -16...16, using: &rng)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            // Drawn upright from the bottom middle.
            cg.translateBy(x: width / 2, y: height)
            cg.scaleBy(x: 1, y: -1)
            func stalkPoint(_ t: CGFloat) -> CGPoint { CGPoint(x: lean * t * t + sin(t * 7) * 4, y: (height - 12) * t) }

            let stalk = CGMutablePath()
            stalk.move(to: .zero)
            for i in 1...24 { stalk.addLine(to: stalkPoint(CGFloat(i) / 24)) }
            cg.addPath(stalk)
            cg.setStrokeColor(UIColor(red: 0.22 * dim, green: 0.27 * dim, blue: 0.08 * dim, alpha: alpha).cgColor)
            cg.setLineWidth(2.5)
            cg.setLineCap(.round)
            cg.strokePath()

            var t: CGFloat = 0.06, side: CGFloat = Bool.random(using: &rng) ? 1 : -1
            while t < 0.97 {
                let base = stalkPoint(t)
                let length = CGFloat.random(in: 26...40, using: &rng) * (1 - 0.3 * t) * blades
                let breadth = CGFloat.random(in: 7...10, using: &rng) * blades
                let angle = side * CGFloat.random(in: 0.5...0.95, using: &rng)
                let shade = shades[min(2, Int(t * 3))]
                let blade = CGMutablePath()
                addBlade(to: blade, at: base, length: length, breadth: breadth, angle: angle)
                blade.addEllipse(in: CGRect(x: base.x - 2.6, y: base.y - 2.6, width: 5.2, height: 5.2))
                cg.addPath(blade)
                cg.setFillColor(UIColor(red: shade.red * dim, green: shade.green * dim, blue: shade.blue * dim, alpha: alpha).cgColor)
                cg.setStrokeColor(UIColor(red: shade.red * dim * 0.7, green: shade.green * dim * 0.7,
                                          blue: shade.blue * dim * 0.7, alpha: alpha * 0.6).cgColor)
                cg.setLineWidth(0.8)
                cg.drawPath(using: .fillStroke)
                side = -side
                t += CGFloat.random(in: 18...26, using: &rng) / height / blades.squareRoot()
            }
        }
        return SKTexture(image: image)
    }

    /// A long, gently curved blade from `base`, tilted `angle` radians off upright toward its side.
    private static func addBlade(to path: CGMutablePath, at base: CGPoint, length: CGFloat, breadth: CGFloat, angle: CGFloat) {
        let direction = CGVector(dx: sin(angle), dy: cos(angle))
        let normal = CGVector(dx: direction.dy, dy: -direction.dx)
        let tip = CGPoint(x: base.x + direction.dx * length, y: base.y + direction.dy * length - length * 0.12)
        let middle = CGPoint(x: base.x + direction.dx * length * 0.5, y: base.y + direction.dy * length * 0.5)
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: middle.x + normal.dx * breadth, y: middle.y + normal.dy * breadth))
        path.addQuadCurve(to: base, control: CGPoint(x: middle.x - normal.dx * breadth, y: middle.y - normal.dy * breadth))
        path.closeSubpath()
    }
}
