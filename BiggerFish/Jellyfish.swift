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

/// Procedural artwork drawn to the hitbox: the bell's top (the bounce surface) peaks at 0.65 of its
/// radius, and the stinging tentacles hang inside the curtain below it, 0.72 of the radius to each
/// side and `tentacleLength` deep. The bell swims in strokes, the tentacles ripple and trail behind
/// its drift, and both react to bounces and stings.
final class JellyfishNode: SKNode {
    private struct Strand {
        let outer: SKShapeNode
        let core: SKShapeNode?
        let color: SKColor
        let baseX: CGFloat
        let length: CGFloat
        let wave: CGFloat
        /// Side-to-side ripple at the tip.
        let sway: CGFloat
        let speed: CGFloat
    }

    /// One swim stroke: a quick squeeze, then a slow release.
    static let strokeSeconds: CGFloat = 1.7
    private static let squeezeShare: CGFloat = 0.28
    private static let stingFlashSeconds: CGFloat = 0.6
    private static let tentacleColor = SKColor(red: 1, green: 0.36, blue: 0.68, alpha: 0.92)
    private static let armColor = SKColor(red: 0.92, green: 0.42, blue: 0.78, alpha: 0.72)

    private let bell = SKNode()
    private var strands: [Strand] = []
    private let radius: CGFloat
    private let phase: CGFloat
    private var time: CGFloat = 0
    private var stungAt: CGFloat?
    private var trail: CGFloat = 0

    init(radius r: CGFloat, tentacleLength: CGFloat, phase: CGFloat, night: Bool = false) {
        radius = r
        self.phase = phase
        super.init()

        // A soft glow: stacked faint ellipses fade out toward the edge.
        for scale in [CGFloat(1), 0.8, 0.62] {
            let halo = SKShapeNode(ellipseOf: CGSize(width: r * 2.6 * scale, height: r * 2 * scale))
            halo.position = CGPoint(x: 0, y: r * 0.2)
            halo.fillColor = SKColor(red: 0.55, green: 0.9, blue: 1, alpha: night ? 0.06 : 0.03)
            halo.strokeColor = .clear
            halo.zPosition = -1
            addChild(halo)
        }

        // Tentacles fan across the curtain; two frilly oral arms hang in the middle.
        let tentacleLengths: [CGFloat] = [0.9, 0.84, 0.95, 0.88, 0.94, 0.83, 0.91]
        for (i, share) in tentacleLengths.enumerated() {
            let thick = i.isMultiple(of: 2)
            strands.append(makeStrand(baseX: (CGFloat(i) - 3) / 3 * r * 0.56, length: tentacleLength * share,
                width: thick ? 3.4 : 2, core: thick ? 1.3 : nil, color: Self.tentacleColor,
                wave: CGFloat(i) * 1.9, sway: 5, speed: 2.6 + CGFloat(i % 3) * 0.3))
        }
        for (i, side) in [CGFloat(-1), 1].enumerated() {
            strands.append(makeStrand(baseX: side * r * 0.13, length: tentacleLength * 0.55,
                width: 7, core: 2.4, color: Self.armColor, wave: CGFloat(i) * 2.4 + 0.7, sway: 7, speed: 1.7))
        }

        let dome = SKShapeNode(path: Self.bellPath(r))
        dome.fillColor = SKColor(red: 0.55, green: 0.85, blue: 1, alpha: 0.68)
        dome.strokeColor = SKColor(red: 0.86, green: 0.97, blue: 1, alpha: 0.95)
        dome.lineWidth = 3
        dome.glowWidth = 1.5
        bell.addChild(dome)

        var inset = CGAffineTransform(scaleX: 0.74, y: 0.68)
        if let inner = Self.bellPath(r).copy(using: &inset) {
            let node = SKShapeNode(path: inner)
            node.fillColor = SKColor(white: 1, alpha: 0.17)
            node.strokeColor = .clear
            node.position = CGPoint(x: 0, y: r * 0.04)
            bell.addChild(node)
        }

        // A moon jelly's four-leaf clover, then a glossy highlight like the fish have.
        for angle in stride(from: CGFloat.pi / 4, to: 2 * .pi, by: .pi / 2) {
            let ring = SKShapeNode(ellipseOf: CGSize(width: r * 0.2, height: r * 0.15))
            ring.position = CGPoint(x: cos(angle) * r * 0.15, y: r * 0.27 + sin(angle) * r * 0.1)
            ring.strokeColor = SKColor(red: 1, green: 0.6, blue: 0.86, alpha: 0.6)
            ring.fillColor = SKColor(red: 1, green: 0.75, blue: 0.92, alpha: 0.18)
            ring.lineWidth = 2.2
            bell.addChild(ring)
        }
        let shine = CGMutablePath()
        shine.move(to: CGPoint(x: -r * 0.66, y: r * 0.2))
        shine.addQuadCurve(to: CGPoint(x: -r * 0.2, y: r * 0.56), control: CGPoint(x: -r * 0.6, y: r * 0.52))
        let highlight = SKShapeNode(path: shine)
        highlight.strokeColor = SKColor(white: 1, alpha: 0.75)
        highlight.lineWidth = 3.5
        highlight.lineCap = .round
        bell.addChild(highlight)
        let glint = SKShapeNode(circleOfRadius: r * 0.05)
        glint.position = CGPoint(x: -r * 0.04, y: r * 0.55)
        glint.fillColor = SKColor(white: 1, alpha: 0.8)
        glint.strokeColor = .clear
        bell.addChild(glint)

        bell.zPosition = 2
        addChild(bell)
        animate(time: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Dome from rim to rim, peaking at 0.66 r, with a scalloped lower edge.
    private static func bellPath(_ r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -r, y: 0))
        path.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: -r, y: r * 0.88), control2: CGPoint(x: r, y: r * 0.88))
        let scallops = 6
        for i in 0..<scallops {
            let from = r - CGFloat(i) * 2 * r / CGFloat(scallops)
            let to = from - 2 * r / CGFloat(scallops)
            path.addQuadCurve(to: CGPoint(x: to, y: 0), control: CGPoint(x: (from + to) / 2, y: -r * 0.13))
        }
        path.closeSubpath()
        return path
    }

    private func makeStrand(baseX: CGFloat, length: CGFloat, width: CGFloat, core: CGFloat?, color: SKColor,
                            wave: CGFloat, sway: CGFloat, speed: CGFloat) -> Strand {
        let outer = SKShapeNode()
        outer.strokeColor = color
        outer.lineWidth = width
        outer.lineCap = .round
        outer.lineJoin = .round
        addChild(outer)
        let coreNode = core.map { width -> SKShapeNode in
            let node = SKShapeNode()
            node.strokeColor = SKColor(red: 1, green: 0.84, blue: 0.94, alpha: 0.75)
            node.lineWidth = width
            node.lineCap = .round
            node.zPosition = 0.1
            addChild(node)
            return node
        }
        return Strand(outer: outer, core: coreNode, color: color, baseX: baseX, length: length, wave: wave,
                      sway: sway, speed: speed)
    }

    /// 0 relaxed ... 1 fully squeezed.
    private func contraction(_ time: CGFloat) -> CGFloat {
        let u = (time / Self.strokeSeconds + phase / (2 * .pi)).truncatingRemainder(dividingBy: 1)
        if u < Self.squeezeShare { return sin(u / Self.squeezeShare * .pi / 2) }
        return 0.5 + 0.5 * cos((u - Self.squeezeShare) / (1 - Self.squeezeShare) * .pi)
    }

    /// `drift` is the bell's velocity in world points per second; the tentacles trail behind it.
    func animate(time: CGFloat, drift: CGVector = .zero) {
        self.time = time
        guard !isHidden else { return }
        let squeeze = contraction(time)
        if bell.action(forKey: "bounce") == nil {
            bell.xScale = 1 - 0.09 * squeeze
            bell.yScale = 1 + 0.11 * squeeze
        }
        trail += ((-drift.dx * 0.2).clamped(-radius * 0.14, radius * 0.14) - trail) * 0.06
        let flash = stungAt.map { max(0, 1 - (time - $0) / Self.stingFlashSeconds) } ?? 0
        if flash == 0 { stungAt = nil }
        for strand in strands {
            let path = strandPath(strand, squeeze: squeeze, shock: flash * 3)
            strand.outer.path = path
            strand.core?.path = path
            strand.outer.strokeColor = flash > 0 ? strand.color.blended(toward: .white, by: flash * 0.75) : strand.color
            strand.outer.glowWidth = flash * 4
        }
    }

    private func strandPath(_ strand: Strand, squeeze: CGFloat, shock: CGFloat) -> CGPath {
        let segments = 7
        let points = (0...segments).map { k -> CGPoint in
            let s = CGFloat(k) / CGFloat(segments)
            let ripple = sin(time * strand.speed - s * 4.6 + strand.wave + phase) * (1 + strand.sway * s)
            let jolt = shock * sin(time * 71 + s * 9 + strand.wave)
            return CGPoint(x: strand.baseX * (1 - 0.16 * squeeze * (1 - 0.6 * s)) + ripple + trail * s * s + jolt,
                           y: -2 - strand.length * s * (1 + 0.05 * squeeze))
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        for k in 1..<segments {
            path.addQuadCurve(to: CGPoint(x: (points[k].x + points[k + 1].x) / 2, y: (points[k].y + points[k + 1].y) / 2),
                              control: points[k])
        }
        path.addLine(to: points[segments])
        return path
    }

    func bounce() {
        bell.removeAction(forKey: "bounce")
        func squash(_ x: CGFloat, _ y: CGFloat, _ duration: TimeInterval) -> SKAction {
            let group = SKAction.group([.scaleX(to: x, duration: duration), .scaleY(to: y, duration: duration)])
            group.timingMode = .easeOut
            return group
        }
        bell.run(.sequence([squash(1.16, 0.62, 0.06), squash(0.94, 1.12, 0.12), squash(1, 1, 0.16)]), withKey: "bounce")
    }

    /// The tentacles flash and jolt when they sting the player.
    func sting() { stungAt = time }
}

/// A stung fish's electric jolt: a flickering glow over the body and zigzag sparks around it.
final class ZapNode: SKNode {
    private static let reference: CGFloat = 30
    private let glow: SKShapeNode
    private let bolts: [SKShapeNode]
    private var sparkSeed: UInt64
    private var lastSparks: CGFloat = -1

    init(seed: UInt64) {
        let R = Self.reference
        sparkSeed = seed
        glow = SKShapeNode(ellipseOf: CGSize(width: R * 3.1, height: R * 2.3))
        glow.fillColor = SKColor(red: 1, green: 0.62, blue: 0.92, alpha: 1)
        glow.strokeColor = .clear
        glow.blendMode = .add
        bolts = (0..<4).map { _ in
            let bolt = SKShapeNode()
            bolt.strokeColor = SKColor(red: 1, green: 0.95, blue: 1, alpha: 1)
            bolt.lineWidth = 2.5
            bolt.lineJoin = .miter
            bolt.glowWidth = 2
            bolt.blendMode = .add
            return bolt
        }
        super.init()
        addChild(glow)
        bolts.forEach(addChild)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// `radius` is the fish's on-screen radius.
    func update(time: CGFloat, radius: CGFloat) {
        setScale(radius / Self.reference)
        glow.alpha = 0.25 + 0.4 * abs(sin(time * 47))
        guard time - lastSparks >= 0.05 else { return }
        lastSparks = time
        var rng = SeededGenerator(seed: sparkSeed)
        sparkSeed = rng.next()
        let R = Self.reference
        for bolt in bolts {
            let angle = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
            let path = CGMutablePath()
            for step in 0...4 {
                let distance = R * (1.1 + CGFloat(step) * 0.24)
                let side = CGFloat.random(in: -0.3...0.3, using: &rng)
                let point = CGPoint(x: cos(angle + side) * distance * 1.25, y: sin(angle + side) * distance)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            bolt.path = path
            bolt.alpha = CGFloat.random(in: 0.5...1, using: &rng)
        }
    }
}

private extension SKColor {
    func blended(toward other: SKColor, by amount: CGFloat) -> SKColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return SKColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount, alpha: a1 + (a2 - a1) * amount)
    }
}
