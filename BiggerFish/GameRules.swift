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
        firstIsPlayer: Bool = false,
        secondIsPlayer: Bool = false,
        nearEqualThreshold: CGFloat = GameTuning.nearEqualThreshold
    ) -> Encounter {
        let big = max(a, b)
        let small = min(a, b)
        guard big > 0 else { return .tooClose }
        if (big - small) / big < nearEqualThreshold {
            if firstIsPlayer != secondIsPlayer { return firstIsPlayer ? .firstEatsSecond : .secondEatsFirst }
            return .tooClose
        }
        return a > b ? .firstEatsSecond : .secondEatsFirst
    }

    /// The visible near-equal band favors the player; NPC ties still bump apart.
    static func playerEncounter(_ player: CGFloat, _ other: CGFloat) -> Encounter {
        encounter(player, other, firstIsPlayer: true)
    }

    /// Area-conserving growth: the predator gains `efficiency` of the prey's area.
    static func grownRadius(
        predator: CGFloat,
        prey: CGFloat,
        efficiency: CGFloat
    ) -> CGFloat {
        sqrt(predator * predator + efficiency * prey * prey)
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
        guard !others.contains(where: { playerEncounter(player.radius, $0.radius) == .firstEatsSecond }) else { return false }
        return mealsEaten < requiredMeals || !others.isEmpty
    }

    /// Campaign wins use the default last-fish-alive rule. Optional meal goals are dormant.
    static func isWin(_ fish: [Fish], mealsEaten: Int = 0, requiredMeals: Int = 0) -> Bool {
        guard mealsEaten >= requiredMeals else { return false }
        guard let player = fish.first(where: \.isPlayer), player.isAlive else { return false }
        return fish.allSatisfy { $0.isPlayer || $0.state == .removed }
    }
}
