import CoreGraphics
import Foundation
import FishKit

/// A design target, not a measured human win probability.
struct EncounterDifficulty: Codable, Equatable {
    var value: Double
    var bounded: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    /// A fractional meal budget makes target size continuous between integer catch requirements.
    var catchBudget: Double { GameTuning.encounterCatchBudget.lowerBound + (GameTuning.encounterCatchBudget.upperBound - GameTuning.encounterCatchBudget.lowerBound) * bounded }
    var minimumCatches: Int { minimumCatches(efficiency: GameTuning.encounterAbsorption * GameTuning.mealGrowthScale) }
    func minimumCatches(efficiency: CGFloat) -> Int {
        let food = GameTuning.encounterFoodRadius
        let target = returnRadius(food: food, efficiency: efficiency)
        var player: CGFloat = 1
        for catches in 0...(GameTuning.encounterCount * GameTuning.encounterFoodCount) {
            if GameRules.playerEncounter(player, target) == .firstEatsSecond { return catches }
            player = GameRules.grownRadius(predator: player, prey: food, efficiency: efficiency)
        }
        return GameTuning.encounterCount * GameTuning.encounterFoodCount + 1
    }
    var spareCatches: Int { GameTuning.encounterCount * GameTuning.encounterFoodCount - minimumCatches }
    /// Easy areas survive one extra circuit; the hardest release immediately behind the player.
    var recoveryPasses: Double { 1 - bounded }
    var clearance: CGFloat { GameTuning.encounterClearance.upperBound - (GameTuning.encounterClearance.upperBound - GameTuning.encounterClearance.lowerBound) * CGFloat(bounded) }

    func returnRadius(food: CGFloat, efficiency: CGFloat) -> CGFloat {
        sqrt(1 + CGFloat(catchBudget) * efficiency * food * food)
    }
}

/// Protection follows forward world distance, independent of camera zoom or wall-clock time.
struct EncounterLease {
    let home: CGPoint
    let releaseDistance: CGFloat
    var index: Int = 0
    func isProtected(distance: CGFloat) -> Bool { distance < releaseDistance }
}

struct EncounterFormation {
    let name: String
    /// x is in screen widths; y is a world-point lift above the safe food baseline.
    let foodOffsets: [CGPoint]
    let threatOffset: CGFloat
}

enum EncounterSteering {
    /// Relative position points away from the neighbor. Only approaching or overlapping pairs steer.
    static func separation(relative: CGVector, velocity: CGVector, reach: CGFloat,
                           stableDirection: CGFloat) -> CGVector? {
        let speedSquared = velocity.dx * velocity.dx + velocity.dy * velocity.dy
        let time = speedSquared > 0
            ? min(GameTuning.encounterSeparationLookAhead,
                max(0, -(relative.dx * velocity.dx + relative.dy * velocity.dy) / speedSquared)) : 0
        let x = relative.dx + velocity.dx * time, y = relative.dy + velocity.dy * time
        guard hypot(x, y) < reach else { return nil }
        let distance = hypot(relative.dx, relative.dy)
        let strength = GameTuning.encounterSeparationSpeed * (1 - min(1, hypot(x, y) / reach))
        return distance > 0.001
            ? CGVector(dx: relative.dx / distance * strength, dy: relative.dy / distance * strength)
            : CGVector(dx: stableDirection * GameTuning.encounterSeparationSpeed, dy: 0)
    }
}
