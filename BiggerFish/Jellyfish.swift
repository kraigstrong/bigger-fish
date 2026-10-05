import CoreGraphics
import SpriteKit
import FishKit

struct JellyLayout {
    let count: Int
    let radius: CGFloat
    let tentacleLength: CGFloat
    let sway: CGFloat
    let urchinBeds: Int
    let night: Bool
    let maintainsFloorLane: Bool
    let heights: [CGFloat]
    /// Wander slowly around each bell's home (Jelly Bloom 2) instead of the small fixed sway.
    var drifts = false

    init(count: Int, radius: CGFloat = 38, tentacleLength: CGFloat = 90,
         sway: CGFloat = 12, urchinBeds: Int = 0, night: Bool = false, maintainsFloorLane: Bool = false, heights: [CGFloat] = []) {
        self.count = count
        self.radius = radius
        self.tentacleLength = tentacleLength
        self.sway = sway
        self.urchinBeds = urchinBeds
        self.night = night
        self.maintainsFloorLane = maintainsFloorLane
        self.heights = heights
    }
}

/// Stable per-level obstacles, with room between bells and a clear opening.
enum JellyPlacement {
    static func origins(layout: JellyLayout, screenWidth: CGFloat, waterBottom: CGFloat,
                        waterTop: CGFloat, seed: UInt64, variation: CGFloat = 1) -> [CGPoint] {
        guard layout.count > 0 else { return [] }
        var rng = SeededGenerator(seed: seed)
        let first = screenWidth * CGFloat.random(in: GameTuning.bloomJellyOpeningScreens, using: &rng)
        let last = screenWidth * CGFloat.random(in: GameTuning.bloomJellyLastScreens, using: &rng)
        let gaps = max(0, layout.count - 1)
        let minimum = layout.radius * 2 + layout.sway * 2 + GameTuning.bloomJellySpacingPadding
        let strength = min(1, max(0, variation))
        let weights = (0..<gaps).map { _ in
            1 + (CGFloat.random(in: GameTuning.bloomJellyGapWeight, using: &rng) - 1) * strength
        }
        let weightSum = weights.reduce(0, +)
        let extra = max(0, last - first - CGFloat(gaps) * minimum)
        var x = first
        return (0..<layout.count).map { i in
            if i > 0 { x += minimum + extra * weights[i - 1] / weightSum }
            let fraction = 0.52 + (CGFloat.random(in: GameTuning.bloomJellyHeightRange, using: &rng) - 0.52) * strength
            let floor = waterBottom + layout.tentacleLength
                + GameRules.bloomFloorLaneClearance(fishRadius: GameTuning.baseRadius)
            return CGPoint(x: x, y: max(floor, waterBottom + (waterTop - waterBottom) * fraction))
        }
    }
}

/// Jelly Bloom 2's slow wander: each bell floats side to side and bobs around its home, on its own phase,
/// as a pure function of time so planned fish can predict it.
enum JellyDrift {
    static func position(origin: CGPoint, phase: CGFloat, time: CGFloat, screenWidth: CGFloat, world: WrappedWorld) -> CGPoint {
        CGPoint(x: world.wrap(origin.x + sin(time * 2 * .pi / GameTuning.jellyDriftSeconds + phase)
                    * screenWidth * GameTuning.jellyDriftScreens),
                y: origin.y + sin(time * 2 * .pi / GameTuning.jellyBobSeconds + phase * 1.3) * GameTuning.jellyBobPoints)
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

    /// Estimate the contact fraction from the fish's clearance above the curved dome.
    /// Spend only the post-contact portion of this frame moving upward.
    static func remainingBounceTime(at p: CGPoint, previous: CGPoint, fishRadius: CGFloat,
                                    domeRadius: CGFloat, dt: CGFloat) -> CGFloat {
        guard dt > 0 else { return 0 }
        let body = fishRadius * GameTuning.hazardHitboxScale
        func clearance(_ point: CGPoint) -> CGFloat {
            let x = min(1, abs(point.x) / (domeRadius + body))
            return point.y - body - domeRadius * 0.65 * sqrt(max(0, 1 - x * x))
        }
        let before = clearance(previous), after = clearance(p)
        // Forgiving contacts can start slightly embedded in the dome.
        guard before > 0 else { return dt }
        guard after < before else { return 0 }
        let contactFraction = min(1, max(0, before / (before - after)))
        return dt * (1 - contactFraction)
    }

    /// Predict a curtain crossing and steer toward a safe vertical exit, turning away if too close.
    /// Bell landings take precedence over steering away from the stingers below them.
    static func avoidance(at p: CGPoint, velocity: CGVector, fishRadius: CGFloat,
                          domeRadius: CGFloat, tentacleLength: CGFloat,
                          minY: CGFloat, maxY: CGFloat, zoom: CGFloat) -> CGVector? {
        let padding = fishRadius * GameTuning.hazardHitboxScale + GameTuning.bloomAvoidancePadding
        let curtain = CGRect(x: -domeRadius * 0.72 - padding, y: -tentacleLength - padding,
                             width: domeRadius * 1.44 + padding * 2, height: tentacleLength + padding * 2)
        let ahead = CGPoint(x: p.x + velocity.dx * GameTuning.bloomAvoidanceLookAhead,
                            y: p.y + velocity.dy * GameTuning.bloomAvoidanceLookAhead)
        guard segmentIntersectsRect(from: p, to: ahead, rect: curtain) else { return nil }
        // The look-ahead can cross the bell and then reach its curtain. Let the real
        // bounce happen if the bell is the first contact, including diagonal landings.
        var previous = p
        for step in 1...GameTuning.jellyAvoidancePredictionSteps {
            let fraction = CGFloat(step) / CGFloat(GameTuning.jellyAvoidancePredictionSteps)
            let point = CGPoint(x: p.x + (ahead.x - p.x) * fraction,
                                y: p.y + (ahead.y - p.y) * fraction)
            let predicted = contact(at: point, previous: previous, fishRadius: fishRadius,
                                    domeRadius: domeRadius, tentacleLength: tentacleLength)
            if predicted == .bounce { return nil }
            if predicted == .tentacles { break }
            previous = point
        }
        let above = curtain.maxY + domeRadius * 0.65
        let below = curtain.minY
        let canGoBelow = below >= minY
        let goUp = above <= maxY && (!canGoBelow || abs(above - p.y) <= abs(below - p.y))
        let targetY = goUp ? above : (canGoBelow ? below : maxY)
        let riseSpeed = GameTuning.bloomAvoidanceRiseSpeed / zoom
        let vertical = targetY >= p.y ? riseSpeed : -riseSpeed
        let exitTime = abs(targetY - p.y) / riseSpeed
        let horizontalGap = max(0, abs(p.x) - curtain.maxX)
        let arrivalTime = horizontalGap / max(1, abs(velocity.dx))
        let horizontal = arrivalTime < exitTime + 0.2
            ? (p.x >= 0 ? 1 : -1) * max(20, abs(velocity.dx)) : velocity.dx
        return CGVector(dx: horizontal, dy: vertical)
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
