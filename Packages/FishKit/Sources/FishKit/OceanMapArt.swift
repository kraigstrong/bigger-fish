import SpriteKit

/// Presentation-only artwork shared by the two games; progress and rewards stay app-owned.
public enum OceanMapArt {
    /// Sandy seabed with a few coral bumps along the bottom of the screen.
    public static func seabed(size: CGSize) -> SKNode {
        let node = SKNode()
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: size.height * 0.14))
        let waves = 5
        for i in 0..<waves {
            let x0 = size.width * CGFloat(i) / CGFloat(waves), x1 = size.width * CGFloat(i + 1) / CGFloat(waves)
            path.addQuadCurve(to: CGPoint(x: x1, y: size.height * (i.isMultiple(of: 2) ? 0.12 : 0.15)),
                              control: CGPoint(x: (x0 + x1) / 2, y: size.height * (i.isMultiple(of: 2) ? 0.19 : 0.09)))
        }
        path.addLine(to: CGPoint(x: size.width, y: 0))
        path.closeSubpath()
        let sand = SKShapeNode(path: path)
        sand.fillColor = SKColor(red: 0.93, green: 0.82, blue: 0.58, alpha: 0.85)
        sand.strokeColor = .clear
        node.addChild(sand)

        let corals: [(x: CGFloat, r: CGFloat, color: SKColor)] = [
            (0.06, 16, SKColor(red: 0.98, green: 0.45, blue: 0.55, alpha: 0.9)),
            (0.09, 10, SKColor(red: 0.98, green: 0.65, blue: 0.35, alpha: 0.9)),
            (0.47, 12, SKColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 0.9)),
            (0.51, 18, SKColor(red: 0.62, green: 0.45, blue: 0.95, alpha: 0.9)),
            (0.93, 14, SKColor(red: 0.98, green: 0.45, blue: 0.55, alpha: 0.9)),
        ]
        for coral in corals {
            let blob = SKShapeNode(ellipseOf: CGSize(width: coral.r * 2, height: coral.r * 2.4))
            blob.position = CGPoint(x: size.width * coral.x, y: size.height * 0.12 + coral.r * 0.6)
            blob.fillColor = coral.color
            blob.strokeColor = .clear
            blob.zPosition = 1
            node.addChild(blob)
        }
        return node
    }

    /// Dotted trail through `points`, gently curved between each pair.
    public static func dottedPath(through points: [CGPoint], spacing: CGFloat = 16) -> SKNode {
        let node = SKNode()
        for (from, to) in zip(points, points.dropFirst()) {
            let control = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + (to.y > from.y ? -24 : 24))
            let steps = max(2, Int(hypot(to.x - from.x, to.y - from.y) / spacing))
            for step in 1..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                let u = 1 - t
                let point = CGPoint(
                    x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                    y: u * u * from.y + 2 * u * t * control.y + t * t * to.y
                )
                let dot = SKShapeNode(circleOfRadius: 3)
                dot.position = point
                dot.fillColor = SKColor(white: 1, alpha: 0.45)
                dot.strokeColor = .clear
                node.addChild(dot)
            }
        }
        return node
    }

}
