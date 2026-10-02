import CoreGraphics
import FishKit

// Bigger Fish campaign rules (relative-size eating, growth, winning).

enum Encounter: Equatable {
    case firstEatsSecond
    case secondEatsFirst
    /// Radii are within the near-equality threshold: bump apart, nobody eats.
    case tooClose
}

enum GameRules {
    static func encounter(
        _ a: CGFloat,
        _ b: CGFloat,
        nearEqualThreshold: CGFloat = GameTuning.nearEqualThreshold
    ) -> Encounter {
        let big = max(a, b)
        let small = min(a, b)
        guard big > 0, (big - small) / big >= nearEqualThreshold else { return .tooClose }
        return a > b ? .firstEatsSecond : .secondEatsFirst
    }

    /// A pursuing predator remains slower than the player horizontally and vertically.
    static func bloomChaseVelocity(offset: CGVector,
                                   playerSpeed: CGFloat, zoom: CGFloat) -> CGVector {
        let horizontal = playerSpeed * GameTuning.bloomChaseSpeedFraction
        let verticalCap = GameTuning.motion.maxRiseSpeed * GameTuning.bloomChaseVerticalFraction / zoom
        return CGVector(dx: (offset.dx >= 0 ? 1 : -1) * horizontal,
                        dy: (offset.dy * 0.9).clamped(-verticalCap, verticalCap))
    }

    /// Area-conserving growth: the predator gains `efficiency` of the prey's area.
    static func grownRadius(
        predator: CGFloat,
        prey: CGFloat,
        efficiency: CGFloat
    ) -> CGFloat {
        sqrt(predator * predator + efficiency * prey * prey)
    }

    /// Ordinary swimmers anticipate a swept circle around an urchin and escape upward.
    static func bloomUrchinAvoidance(at p: CGPoint, velocity: CGVector, fishRadius: CGFloat,
                                     zoom: CGFloat) -> CGVector? {
        let seconds = GameTuning.bloomAvoidanceLookAhead
        let delta = CGVector(dx: velocity.dx * seconds, dy: velocity.dy * seconds)
        let length = delta.dx * delta.dx + delta.dy * delta.dy
        let fraction = length > 0 ? (-(p.x * delta.dx + p.y * delta.dy) / length).clamped(0, 1) : 0
        let closest = CGPoint(x: p.x + delta.dx * fraction, y: p.y + delta.dy * fraction)
        let clearance = (GameTuning.urchinRadius + fishRadius) * GameTuning.hazardHitboxScale +
            GameTuning.bloomAvoidancePadding
        guard hypot(closest.x, closest.y) < clearance else { return nil }
        let rise = GameTuning.bloomAvoidanceRiseSpeed / zoom
        let escapeTime = max(0, clearance - p.y) / rise
        let arrivalTime = max(0, abs(p.x) - clearance) / max(1, abs(velocity.dx))
        let horizontal = arrivalTime < escapeTime + 0.2
            ? (p.x >= 0 ? 1 : -1) * max(20, abs(velocity.dx)) : velocity.dx
        return CGVector(dx: horizontal, dy: rise)
    }

    /// A grown fish fits between a curtain's tip and the top of an urchin's lethal region.
    static func bloomFloorLaneClearance(fishRadius: CGFloat) -> CGFloat {
        GameTuning.urchinRadius * 0.55 +
        (GameTuning.urchinRadius + fishRadius * 2) * GameTuning.hazardHitboxScale +
        GameTuning.bloomFloorLanePadding
    }

    /// Refill only a stalled Bloom ecosystem, never a normal final chase or an active swallow.
    static func needsFood(_ fish: [Fish], mealsEaten: Int, requiredMeals: Int) -> Bool {
        guard requiredMeals > 0,
              let player = fish.first(where: \.isPlayer), player.state == .swimming else { return false }
        let others = fish.filter { !$0.isPlayer && $0.state != .removed }
        guard !others.contains(where: { encounter(player.radius, $0.radius) == .firstEatsSecond }) else { return false }
        return mealsEaten < requiredMeals || !others.isEmpty
    }

    /// Campaign wins use the default last-fish-alive rule. Optional meal goals are dormant.
    static func isWin(_ fish: [Fish], mealsEaten: Int = 0, requiredMeals: Int = 0) -> Bool {
        guard mealsEaten >= requiredMeals else { return false }
        guard let player = fish.first(where: \.isPlayer), player.isAlive else { return false }
        return fish.allSatisfy { $0.isPlayer || $0.state == .removed }
    }
}
