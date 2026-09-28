import CoreGraphics

enum FishState: Equatable {
    case swimming
    case swallowing(preyID: Int)
    case beingSwallowed(predatorID: Int)
    case removed
}

/// Simulation state for one fish. The player and AI fish share the same rules;
/// the AI steering fields are simply unused for the player.
final class Fish {
    let id: Int
    let isPlayer: Bool
    var position: CGPoint
    var velocity = CGVector.zero
    /// Current rendered (and therefore gameplay) radius. Animates toward `targetRadius` after eating.
    var radius: CGFloat
    var targetRadius: CGFloat
    var state: FishState = .swimming

    // Growth animation
    var growFrom: CGFloat = 0
    var growElapsed: CGFloat = .greatestFiniteMagnitude

    // AI steering
    var heading: CGFloat = 1
    var cruiseSpeed: CGFloat = 0
    var targetY: CGFloat = 0
    var retargetTimer: CGFloat = 0
    var turnTimer: CGFloat = 0
    var phase: CGFloat = 0

    // Visual-only state
    /// -1...1; sign is the direction the fish faces, magnitude < 1 while turning.
    var facing: CGFloat = 1
    var pulse: CGFloat = 0
    var squash: CGFloat = 0
    var shrink: CGFloat = 1
    var struggle: CGFloat = 0

    init(id: Int, isPlayer: Bool, position: CGPoint, radius: CGFloat) {
        self.id = id
        self.isPlayer = isPlayer
        self.position = position
        self.radius = radius
        self.targetRadius = radius
    }

    var isAlive: Bool {
        switch state {
        case .swimming, .swallowing: true
        case .beingSwallowed, .removed: false
        }
    }
}

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

    /// Area-conserving growth: the predator gains `efficiency` of the prey's area.
    static func grownRadius(
        predator: CGFloat,
        prey: CGFloat,
        efficiency: CGFloat = GameTuning.absorptionEfficiency
    ) -> CGFloat {
        sqrt(predator * predator + efficiency * prey * prey)
    }

    /// Nearly equal swallows take longer so the player feels how close the call was.
    static func swallowDuration(sizeRatio: CGFloat) -> CGFloat {
        let curve = GameTuning.swallowDurationCurve
        guard let first = curve.first, let last = curve.last else { return 0.3 }
        if sizeRatio <= first.ratio { return first.seconds }
        if sizeRatio >= last.ratio { return last.seconds }
        for (lo, hi) in zip(curve, curve.dropFirst()) where sizeRatio <= hi.ratio {
            let t = (sizeRatio - lo.ratio) / (hi.ratio - lo.ratio)
            return lo.seconds + (hi.seconds - lo.seconds) * t
        }
        return last.seconds
    }

    /// The player wins by being the only fish left alive.
    static func isWin(_ fish: [Fish]) -> Bool {
        guard let player = fish.first(where: \.isPlayer), player.isAlive else { return false }
        return fish.allSatisfy { $0.isPlayer || $0.state == .removed }
    }
}
