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

    /// You win as the last fish swimming.
    static func isWin(_ fish: [Fish]) -> Bool {
        guard let player = fish.first(where: \.isPlayer), player.isAlive else { return false }
        return fish.allSatisfy { $0.isPlayer || $0.state == .removed }
    }

    /// You can't win any more: there are fish left (`others`, here or still to swim in, each at its full size), and
    /// you're too small to eat any of them. No fish ever shrinks, hazards never take one, and you grow only by eating, so
    /// once this is true it stays true. (No fish left at all is a win, not this.)
    static func isTooSmallToWin(player: CGFloat, others: [CGFloat]) -> Bool {
        !others.isEmpty && others.allSatisfy { playerEncounter(player, $0) != .firstEatsSecond }
    }
}
