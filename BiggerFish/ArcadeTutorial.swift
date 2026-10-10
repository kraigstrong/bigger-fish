import CoreGraphics
import FishKit
import SpriteKit

/// Bigger Fish's first-launch tutorial: five short beats, the same every time, that teach the race at the heart of
/// the game. Eat smaller fish, steer clear of bigger ones, and eat on your first pass: a fish you miss keeps eating,
/// swims on round the reef, and comes back bigger. Then the gates every level has: eat enough to get through. The
/// fish swim scripted paths, but every bite is the game's own (the same collisions, swallows, and growth as a
/// level), so you watch a missed fish's real size change.
enum ArcadeTutorial {
    enum Beat: Int, CaseIterable {
        /// One small glowing fish ahead.
        case eatSmaller
        /// A bigger fish swims at you: go around it.
        case dodgeBigger
        /// A fish you pass eats two little ones as it goes by, and swims on.
        case missedFishEats
        /// One more glowing meal, and the fish that outgrew you comes round again: yours.
        case catchItBack
        /// A wall of three fish, a little bigger than you: two easy meals, then eat your way through.
        case eatEnough

        /// The one short line shown with the beat.
        var caption: String {
            switch self {
            case .eatSmaller: "Eat smaller fish"
            case .dodgeBigger: "Avoid bigger fish"
            case .missedFishEats: "Fish you miss keep eating"
            case .catchItBack: "Grow, then catch it"
            case .eatEnough: "Eat enough to get through"
            }
        }

        /// Where a retry starts after being eaten: the race's two beats go together.
        var checkpoint: Beat { self == .catchItBack ? .missedFishEats : self }
    }

    /// The card before it starts, and the line it ends on before fading to the map.
    static let title = "Bigger Fish"
    static let card = ["Hold anywhere to rise.", "Let go to fall."]
    static let finale = "Now you're ready to play!"

    /// Your radius at the start of a beat, eating what the beats before it fed you.
    static func radius(startingAt beat: Beat) -> CGFloat {
        let base = GameTuning.baseRadius
        guard beat != .eatSmaller else { return base }
        let afterFirst = grow(base, eating: GameTuning.tutorialFirstMeal)
        guard beat == .eatEnough else { return afterFirst }
        let afterLast = grow(afterFirst, eating: lastMeal(you: afterFirst, rival: missedFishGrown))
        return grow(afterLast, eating: missedFishGrown)
    }

    /// The missed fish after eating its two meals.
    static var missedFishGrown: CGFloat {
        let meal = GameTuning.tutorialMissedFishMeal
        return grow(grow(GameTuning.tutorialMissedFish, eating: meal), eating: meal)
    }

    /// A last meal that takes a fish of `you` to `GameTuning.tutorialCatchMargin` times `rival`, within sensible
    /// meal sizes. Worked out from the sizes as they are, so it still fits if the race went differently.
    static func lastMeal(you: CGFloat, rival: CGFloat) -> CGFloat {
        let goal = rival * GameTuning.tutorialCatchMargin
        let needed = (goal * goal - you * you) / efficiency
        return min(you * 0.85, max(8, needed > 0 ? needed.squareRoot() : 8))
    }

    // MARK: The race

    /// When each of the missed fish's two meals sets off, in seconds before the missed fish does: they swim ahead of
    /// it, slower, so it catches each where `tutorialMissedCatches` puts it. A bite starts as soon as the two touch,
    /// so each meal is that far further on when it's caught (the fish is bigger by the second).
    static var missedMealLeads: [CGFloat] {
        let meal = GameTuning.tutorialMissedFishMeal, eaters = [GameTuning.tutorialMissedFish, grow(GameTuning.tutorialMissedFish, eating: meal)]
        let screen = GameTuning.playfieldSize.width / GameTuning.tutorialZoom
        return zip(GameTuning.tutorialMissedCatches, eaters).map { at, eater in
            let touch = (eater + meal) * GameTuning.collisionScale / screen
            return (TutorialPath.enters - (at - touch)) / GameTuning.tutorialMissedMealSpeed
                - (TutorialPath.enters - at) / GameTuning.tutorialMissedFishSpeed
        }
    }

    // MARK: The wall

    /// The wall's fish, for a fish of `you`.
    static func wallFish(you: CGFloat) -> CGFloat { you * GameTuning.tutorialWallSize }

    /// Each of the `meals` meals still to come before the wall (two at first): together they make you
    /// `GameTuning.tutorialWallMargin` times a wall fish, and one of two isn't enough.
    static func wallMeal(you: CGFloat, wall: CGFloat, meals: Int = 2) -> CGFloat {
        let goal = wall * GameTuning.tutorialWallMargin
        return max(8, ((goal * goal - you * you) / (CGFloat(max(1, meals)) * efficiency)).squareRoot())
    }

    /// Where the wall's three fish swim (world heights, bottom to top) for water from `bottom` to `top`: the outer
    /// two reach the floor and the surface for a fish of `you`, the middle one sits between, and none leave room to
    /// slip past.
    static func wallHeights(you: CGFloat, wall: CGFloat, bottom: CGFloat, top: CGFloat) -> [CGFloat] {
        let reach = (you + wall) * GameTuning.collisionScale
        let lowest = bottom + you * 0.95 + reach * 0.85, highest = top - you * 0.95 - reach * 0.85
        return [lowest, (lowest + highest) / 2, highest]
    }

    /// Whether a fish of `you` can't get past fish of `wall` at `heights` anywhere it can swim.
    static func wallBlocks(you: CGFloat, wall: CGFloat, heights: [CGFloat], bottom: CGFloat, top: CGFloat) -> Bool {
        let reach = (you + wall) * GameTuning.collisionScale
        return stride(from: bottom + you * 0.95, through: top - you * 0.95, by: 1).allSatisfy { y in
            heights.contains { abs($0 - y) < reach }
        }
    }

    static func grow(_ fish: CGFloat, eating meal: CGFloat) -> CGFloat {
        GameRules.grownRadius(predator: fish, prey: meal, efficiency: efficiency)
    }

    private static var efficiency: CGFloat { GameTuning.tutorialLevel.effectiveAbsorptionEfficiency }

    /// How a beat's fish look: the missed fish is purple and spotted, so you know it again when it comes back; the
    /// wall's three are alike, so they read as one.
    static let missedStyle = FishStyle(body: SKColor(red: 0.61, green: 0.36, blue: 0.90, alpha: 1),
                                       accent: SKColor(red: 0.85, green: 0.72, blue: 1.00, alpha: 1),
                                       pattern: .spots, tail: .fork, eyeScale: 1.1, hasDorsalFin: true)
    static let wallStyle = FishStyle(body: SKColor(red: 0.16, green: 0.62, blue: 0.62, alpha: 1),
                                     accent: SKColor(red: 0.55, green: 0.88, blue: 0.84, alpha: 1),
                                     pattern: .stripes, tail: .fan, eyeScale: 1.0, hasDorsalFin: true)
}

/// A scripted swim measured from you, so it reads the same at any speed: screens ahead of you (negative: behind)
/// and share of the water (0 bottom, 1 top), at seconds since the fish appeared, straight between points and held
/// at the last one after.
struct TutorialPath {
    var points: [(t: CGFloat, ahead: CGFloat, share: CGFloat)]
    var duration: CGFloat { points.last?.t ?? 0 }

    func at(_ t: CGFloat) -> (ahead: CGFloat, share: CGFloat) {
        guard let first = points.first else { return (0, 0.5) }
        if t <= first.t { return (first.ahead, first.share) }
        for (a, b) in zip(points, points.dropFirst()) where t <= b.t {
            let u = (t - a.t) / max(b.t - a.t, 0.0001)
            return (a.ahead + (b.ahead - a.ahead) * u, a.share + (b.share - a.share) * u)
        }
        return (points[points.count - 1].ahead, points[points.count - 1].share)
    }

    /// Just off screen ahead of you, and just off screen behind.
    static let enters: CGFloat = 0.78
    static let leaves: CGFloat = -0.45

    /// Swims straight at you along `share`, from just off screen to behind you, crossing you at `crossing` seconds.
    static func headOn(share: CGFloat, crossing: CGFloat) -> TutorialPath {
        straight(share: share, speed: enters / crossing)
    }

    /// Swims at you along `share` at `speed` screens a second (as it looks on screen), from `from` until it's off
    /// screen behind you.
    static func straight(share: CGFloat, speed: CGFloat, from: CGFloat = enters) -> TutorialPath {
        TutorialPath(points: [(0, from, share), ((from - leaves) / speed, leaves, share)])
    }
}
