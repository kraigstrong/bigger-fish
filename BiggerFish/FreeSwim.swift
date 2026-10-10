import CoreGraphics
import FishKit

/// The free-swimming steering every roaming arcade fish uses. Gameplay and the meeting planner share it,
/// so a planned fish follows exactly the path the planner predicted until something touches it.
enum FreeSwim {
    /// Each fish's own movement stream. Variant 0 is the stream every unplanned fish has always used.
    static func movementGenerator(ecosystemSeed: UInt64, id: Int, variant: UInt64 = 0) -> SeededGenerator {
        var seedMixer = SeededGenerator(seed: ecosystemSeed &+ 0xA0761D6478BD642F
            &+ UInt64(id) &* 0x9E3779B97F4A7C15 &+ variant &* 0xD6E8FEB86659FD93)
        return SeededGenerator(seed: seedMixer.next())
    }

    /// Turns, the optional linger leash, cruising, and vertical wandering. Returns the velocity
    /// before neighbor separation or hazard avoidance adjust it.
    static func steer(_ f: Fish, dt: CGFloat, clock: CGFloat, minY: CGFloat, maxY: CGFloat,
                      verticalSpeed: CGFloat, leash: (offset: CGFloat, halfWidth: CGFloat)?,
                      rng: inout SeededGenerator) -> CGVector {
        f.turnTimer -= dt
        if f.turnTimer <= 0 {
            f.heading *= -1
            f.turnTimer = CGFloat.random(in: GameTuning.aiTurnIntervalRange, using: &rng)
        }
        if let leash, abs(leash.offset) > leash.halfWidth { f.heading = leash.offset > 0 ? -1 : 1 }
        let targetVX = f.heading * f.cruiseSpeed * (1 + 0.15 * sin(clock * 0.7 + f.phase))
        let vx = f.velocity.dx + (targetVX - f.velocity.dx) * min(1, dt * 1.5)

        f.retargetTimer -= dt
        if f.retargetTimer <= 0 || abs(f.targetY - f.position.y) < 6 {
            f.targetY = CGFloat.random(in: minY...maxY, using: &rng)
            f.retargetTimer = CGFloat.random(in: GameTuning.aiRetargetRange, using: &rng)
        }
        f.targetY = f.targetY.clamped(minY, maxY)
        let desiredVY = ((f.targetY - f.position.y) * 0.9).clamped(-verticalSpeed, verticalSpeed)
            + sin(clock * 1.3 + f.phase) * 8
        let vy = f.velocity.dy + (desiredVY - f.velocity.dy) * min(1, dt * 2)
        return CGVector(dx: vx, dy: vy)
    }

    /// Moves the fish, bouncing softly off the top and bottom of the water.
    static func integrate(_ f: Fish, velocity: CGVector, dt: CGFloat, minY: CGFloat, maxY: CGFloat,
                          world: WrappedWorld) {
        var vx = velocity.dx, vy = velocity.dy
        var y = f.position.y + vy * dt
        if y < minY { y = minY; vy = abs(vy) * 0.3 }
        if y > maxY { y = maxY; vy = -abs(vy) * 0.3 }
        if !vx.isFinite { vx = 0 }
        f.velocity = CGVector(dx: vx, dy: vy)
        f.position = CGPoint(x: world.wrap(f.position.x + vx * dt), y: y)
    }
}
