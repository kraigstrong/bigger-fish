import FishKit
import SpriteKit

/// A bed of giant kelp drawn upward from its base at the node's origin: plants with a wavy stalk and blades
/// on alternate sides, each with a small float, shading from dark olive at the roots to sunlit gold at the top.
/// The back bed is darker and grows behind every fish; the front bed is fainter and grows in front of the
/// other fish, so fish inside show through it as silhouettes.
final class KelpNode: SKNode {
    private var plants: [(node: SKNode, phase: CGFloat, rate: CGFloat)] = []

    /// Base, middle, and top colors of the blades, from dark at the roots to sunlit at the top.
    private static let shades: [(red: CGFloat, green: CGFloat, blue: CGFloat)] = [
        (0.27, 0.33, 0.1), (0.45, 0.5, 0.15), (0.66, 0.63, 0.22),
    ]

    init(width: CGFloat, height: CGFloat, seed: UInt64, front: Bool) {
        super.init()
        var rng = SeededGenerator(seed: 0x6B656C70 &+ seed)
        let count = max(front ? 2 : 4, Int(width / (front ? 46 : 24)))
        let dim: CGFloat = front ? 1 : 0.62
        let alpha: CGFloat = front ? 0.5 : 0.95
        for index in 0..<count {
            let x = -width / 2 + width * (CGFloat(index) + CGFloat.random(in: 0.15...0.85, using: &rng)) / CGFloat(count)
            let tall = height * CGFloat.random(in: front ? 0.7...0.95 : 0.8...1.02, using: &rng)
            let plant = Self.plant(height: tall, lean: CGFloat.random(in: -16...16, using: &rng), dim: dim, alpha: alpha,
                                   rng: &rng)
            plant.position = CGPoint(x: x, y: 0)
            addChild(plant)
            plants.append((plant, CGFloat.random(in: 0..<(2 * .pi), using: &rng), CGFloat.random(in: 0.7...1.1, using: &rng)))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func plant(height: CGFloat, lean: CGFloat, dim: CGFloat, alpha: CGFloat,
                              rng: inout SeededGenerator) -> SKNode {
        let node = SKNode()
        func stalkPoint(_ t: CGFloat) -> CGPoint { CGPoint(x: lean * t * t + sin(t * 7) * 4, y: height * t) }

        let stalk = CGMutablePath()
        stalk.move(to: .zero)
        for i in 1...24 { stalk.addLine(to: stalkPoint(CGFloat(i) / 24)) }
        let stem = SKShapeNode(path: stalk)
        stem.strokeColor = SKColor(red: 0.22 * dim, green: 0.27 * dim, blue: 0.08 * dim, alpha: alpha)
        stem.lineWidth = 2.5
        stem.lineCap = .round
        node.addChild(stem)

        // Blades in three height bands, one shape each, so the plant shades from its roots to its tip.
        var bands = [CGMutablePath(), CGMutablePath(), CGMutablePath()]
        var t: CGFloat = 0.08, side: CGFloat = Bool.random(using: &rng) ? 1 : -1
        while t < 0.98 {
            let base = stalkPoint(t)
            let length = CGFloat.random(in: 26...40, using: &rng) * (1 - 0.3 * t)
            let breadth = CGFloat.random(in: 7...10, using: &rng)
            let angle = side * CGFloat.random(in: 0.5...0.95, using: &rng)
            let band = min(2, Int(t * 3))
            Self.addBlade(to: bands[band], at: base, length: length, breadth: breadth, angle: angle)
            bands[band].addEllipse(in: CGRect(x: base.x - 2.6, y: base.y - 2.6, width: 5.2, height: 5.2))
            side = -side
            t += CGFloat.random(in: 18...26, using: &rng) / height
        }
        for (index, path) in bands.enumerated() {
            let shade = shades[index]
            let blades = SKShapeNode(path: path)
            blades.fillColor = SKColor(red: shade.red * dim, green: shade.green * dim, blue: shade.blue * dim, alpha: alpha)
            blades.strokeColor = SKColor(red: shade.red * dim * 0.7, green: shade.green * dim * 0.7,
                                         blue: shade.blue * dim * 0.7, alpha: alpha * 0.6)
            blades.lineWidth = 0.8
            node.addChild(blades)
        }
        return node
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

    func sway(time: CGFloat) {
        for plant in plants {
            plant.node.zRotation = 0.045 * sin(time * 0.9 * plant.rate + plant.phase)
        }
    }
}
