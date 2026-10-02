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
    static func bloomChaseVelocity(offset: CGVector, cruiseSpeed: CGFloat,
                                   playerSpeed: CGFloat, zoom: CGFloat) -> CGVector {
        let horizontal = min(cruiseSpeed * 1.8 / zoom, playerSpeed * GameTuning.bloomChaseSpeedFraction)
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

    /// Refill only a stalled Bloom ecosystem, never a normal final chase or an active swallow.
    static func needsFood(_ fish: [Fish], mealsEaten: Int, requiredMeals: Int) -> Bool {
        guard requiredMeals > 0,
              let player = fish.first(where: \.isPlayer), player.state == .swimming else { return false }
        let others = fish.filter { !$0.isPlayer && $0.state != .removed }
        guard !others.contains(where: { encounter(player.radius, $0.radius) == .firstEatsSecond }) else { return false }
        return mealsEaten < requiredMeals || !others.isEmpty
    }

    /// Bloom also requires completed player meals; hazard and AI kills earn no credit.
    static func isWin(_ fish: [Fish], mealsEaten: Int = 0, requiredMeals: Int = 0) -> Bool {
        guard mealsEaten >= requiredMeals else { return false }
        guard let player = fish.first(where: \.isPlayer), player.isAlive else { return false }
        return fish.allSatisfy { $0.isPlayer || $0.state == .removed }
    }
}
