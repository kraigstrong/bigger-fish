import CoreGraphics
import SpriteKit

struct JellyLayout {
    let count: Int
    let radius: CGFloat
    let tentacleLength: CGFloat
    let sway: CGFloat
    let urchinBeds: Int
    let night: Bool

    init(count: Int, radius: CGFloat = 38, tentacleLength: CGFloat = 90,
         sway: CGFloat = 12, urchinBeds: Int = 0, night: Bool = false) {
        self.count = count
        self.radius = radius
        self.tentacleLength = tentacleLength
        self.sway = sway
        self.urchinBeds = urchinBeds
        self.night = night
    }
}

enum JellyContact: Equatable { case none, bounce, tentacles }

/// Coordinates are relative to the jelly's bell rim (y = 0); tentacles extend down.
/// A swept test catches fast falls through the forgiving top of the dome.
enum JellyRules {
    static func contact(at p: CGPoint, previous: CGPoint, fishRadius: CGFloat,
                        domeRadius r: CGFloat, tentacleLength: CGFloat) -> JellyContact {
        let body = fishRadius * GameTuning.hazardHitboxScale
        let domeTop = r * 0.65
        let domeReach = r + body
        if abs(p.x) <= domeReach {
            let x = min(1, abs(p.x) / domeReach)
            let surface = domeTop * sqrt(max(0, 1 - x * x))
            // Only the upper side is safe: hitting the underside does not grant a bounce.
            if p.y - body <= surface,
               previous.y - body >= surface - GameTuning.jellyDomeForgiveness,
               p.y >= 0 || previous.y - body >= surface {
                return .bounce
            }
        }
        let tentacles = CGRect(x: -r * 0.72, y: -tentacleLength,
                               width: r * 1.44, height: tentacleLength)
        let closest = CGPoint(x: min(tentacles.maxX, max(tentacles.minX, p.x)),
                              y: min(tentacles.maxY, max(tentacles.minY, p.y)))
        if hypot(p.x - closest.x, p.y - closest.y) < body { return .tentacles }
        // A fish can cross the whole curtain during one frame at a high velocity.
        let expanded = tentacles.insetBy(dx: -body, dy: -body)
        if segmentIntersectsRect(from: previous, to: p, rect: expanded) { return .tentacles }
        return .none
    }

    private static func segmentIntersectsRect(from a: CGPoint, to b: CGPoint, rect: CGRect) -> Bool {
        var low: CGFloat = 0, high: CGFloat = 1
        for (start, delta, minimum, maximum) in [
            (a.x, b.x - a.x, rect.minX, rect.maxX),
            (a.y, b.y - a.y, rect.minY, rect.maxY),
        ] {
            if abs(delta) < 0.0001 {
                if start < minimum || start > maximum { return false }
            } else {
                let t1 = (minimum - start) / delta, t2 = (maximum - start) / delta
                low = max(low, min(t1, t2)); high = min(high, max(t1, t2))
                if low > high { return false }
            }
        }
        return true
    }
}

/// Procedural artwork keeps the rounded, safe bell distinct from the trailing danger zone.
final class JellyfishNode: SKNode {
    private let bell = SKNode()
    private let tendrils = SKNode()
    private let radius: CGFloat
    private let phase: CGFloat

    init(radius r: CGFloat, tentacleLength: CGFloat, phase: CGFloat) {
        radius = r
        self.phase = phase
        super.init()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -r, y: 0))
        path.addCurve(to: CGPoint(x: r, y: 0),
                      control1: CGPoint(x: -r, y: r * 0.88),
                      control2: CGPoint(x: r, y: r * 0.88))
        path.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: 0, y: -r * 0.18))
        let dome = SKShapeNode(path: path)
        dome.fillColor = SKColor(red: 0.63, green: 0.76, blue: 1, alpha: 0.62)
        dome.strokeColor = SKColor(red: 0.80, green: 0.95, blue: 1, alpha: 0.95)
        dome.lineWidth = 2.5
        dome.glowWidth = 2
        bell.addChild(dome)
        let rim = SKShapeNode(ellipseOf: CGSize(width: r * 1.85, height: r * 0.16))
        rim.strokeColor = SKColor(red: 0.56, green: 1, blue: 0.97, alpha: 0.95)
        rim.lineWidth = 2
        bell.addChild(rim)
        for i in 0..<7 {
            let x = (CGFloat(i) - 3) * r * 0.25
            let line = CGMutablePath()
            line.move(to: CGPoint(x: x, y: -2))
            line.addCurve(to: CGPoint(x: x + sin(CGFloat(i)) * 8, y: -tentacleLength),
                          control1: CGPoint(x: x + 13, y: -tentacleLength * 0.35),
                          control2: CGPoint(x: x - 13, y: -tentacleLength * 0.72))
            let tentacle = SKShapeNode(path: line)
            tentacle.strokeColor = SKColor(red: 1, green: 0.40, blue: 0.70, alpha: 0.8)
            tentacle.lineWidth = i.isMultiple(of: 2) ? 3.5 : 2
            tentacle.lineCap = .round
            tendrils.addChild(tentacle)
        }
        addChild(tendrils)
        addChild(bell)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func animate(time: CGFloat) {
        let pulse = sin(time * 2.6 + phase)
        if bell.action(forKey: "bounce") == nil { bell.yScale = 1 + pulse * 0.08 }
        tendrils.zRotation = sin(time * 1.5 + phase) * 0.055
    }

    func bounce() {
        bell.removeAction(forKey: "bounce")
        bell.run(.sequence([.scaleY(to: 0.6, duration: 0.06), .scaleY(to: 1.1, duration: 0.12),
                            .scaleY(to: 1, duration: 0.14)]), withKey: "bounce")
    }
}
