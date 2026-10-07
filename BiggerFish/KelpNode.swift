import FishKit
import SpriteKit

/// A bed of kelp drawn upward from its base at the node's origin: a few swaying stalks with blades,
/// translucent enough that fish inside show through as silhouettes.
final class KelpNode: SKNode {
    private var stalks: [(node: SKShapeNode, phase: CGFloat)] = []

    init(width: CGFloat, height: CGFloat, seed: UInt64) {
        super.init()
        var rng = SeededGenerator(seed: 0x6B656C70 &+ seed)
        let count = max(3, Int(width / 26))
        for index in 0..<count {
            let x = -width / 2 + width * (CGFloat(index) + CGFloat.random(in: 0.2...0.8, using: &rng)) / CGFloat(count)
            let tall = height * CGFloat.random(in: 0.8...1, using: &rng)
            let stalk = SKShapeNode(path: Self.stalkPath(height: tall, lean: CGFloat.random(in: -12...12, using: &rng)))
            let green = CGFloat.random(in: 0.42...0.58, using: &rng)
            stalk.fillColor = SKColor(red: 0.16, green: green, blue: 0.2, alpha: 0.72)
            stalk.strokeColor = SKColor(red: 0.1, green: green * 0.7, blue: 0.12, alpha: 0.8)
            stalk.lineWidth = 1.5
            stalk.position = CGPoint(x: x, y: 0)
            addChild(stalk)
            stalks.append((stalk, CGFloat.random(in: 0..<(2 * .pi), using: &rng)))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A wavy stalk with a blade off each side every so often, as one filled outline from the base.
    private static func stalkPath(height: CGFloat, lean: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let segments = max(3, Int(height / 34))
        path.move(to: CGPoint(x: -3, y: 0))
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments), y = height * t
            let x = lean * t * t + sin(t * 9) * 5
            let half = 3.5 * (1 - 0.6 * t)
            left.append(CGPoint(x: x - half, y: y))
            right.append(CGPoint(x: x + half, y: y))
        }
        for (i, point) in left.enumerated() {
            path.addLine(to: point)
            // Blades hang off alternate sides.
            if i > 0 && i < segments && i % 2 == 1 {
                path.addQuadCurve(to: point, control: CGPoint(x: point.x - 26, y: point.y + 22))
            }
        }
        for (i, point) in right.enumerated().reversed() {
            path.addLine(to: point)
            if i > 0 && i < segments && i % 2 == 0 {
                path.addQuadCurve(to: point, control: CGPoint(x: point.x + 26, y: point.y + 22))
            }
        }
        path.closeSubpath()
        return path
    }

    func sway(time: CGFloat) {
        for (stalk, phase) in stalks {
            stalk.zRotation = 0.05 * sin(time * 1.1 + phase)
        }
    }
}
