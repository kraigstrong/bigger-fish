import CoreGraphics
import FishKit
import SpriteKit

/// Bigger Fish's first-launch tutorial: four short beats, the same every time, that teach the race at the heart of
/// the game. Eat smaller fish, steer clear of bigger ones, and eat on your first pass: a fish you miss keeps
/// eating behind you and grows. The fish swim scripted paths, but every bite is the game's own (the same collisions,
/// swallows, and growth as a level), so you watch a missed fish's real size change.
enum ArcadeTutorial {
    enum Beat: Int, CaseIterable {
        /// One small glowing fish ahead.
        case eatSmaller
        /// A bigger fish swims at you: go around it.
        case dodgeBigger
        /// A fish you pass eats two little ones behind you and outgrows you.
        case missedFishEats
        /// One more glowing meal, and the fish that outgrew you is yours.
        case catchItBack

        /// The one short line shown with the beat.
        var caption: String {
            switch self {
            case .eatSmaller: "Eat smaller fish"
            case .dodgeBigger: "Avoid bigger fish"
            case .missedFishEats: "Fish you miss keep eating"
            case .catchItBack: "Grow, then catch it"
            }
        }

        /// Where a retry starts after being eaten: the race's two beats go together.
        var checkpoint: Beat { self == .catchItBack ? .missedFishEats : self }
    }

    /// The card before it starts.
    static let title = "Bigger Fish"
    static let card = ["Hold anywhere to rise.", "Let go to fall."]

    /// Sizes (radius; you start at `GameTuning.baseRadius`, 16). With the tutorial's growth, the first meal takes
    /// you to 18.4; the missed fish (14) eats two little ones (12) and reaches 20.7, clearly bigger than you; the
    /// last meal (14) takes you to 22.3, just past it.
    static let firstMeal: CGFloat = 10
    static let bigFish: CGFloat = 40
    static let missedFish: CGFloat = 14
    static let missedFishMeal: CGFloat = 12
    static let lastMeal: CGFloat = 14

    /// A slow, roomy level whose fish can eat each other, with no fish of its own: the beats bring theirs.
    static let level = Level(spawnGroups: [], aiSpeedRange: 40...90, aiVerticalSpeed: 50, screenCrossSeconds: 3.2,
                             absorptionEfficiency: 0.9)

    /// Your radius at the start of a beat, eating what the beats before it fed you.
    static func radius(startingAt beat: Beat) -> CGFloat {
        let base = GameTuning.baseRadius
        return beat == .eatSmaller ? base
            : GameRules.grownRadius(predator: base, prey: firstMeal, efficiency: level.effectiveAbsorptionEfficiency)
    }

    /// The missed fish after eating its two meals.
    static var missedFishGrown: CGFloat {
        let once = GameRules.grownRadius(predator: missedFish, prey: missedFishMeal, efficiency: level.effectiveAbsorptionEfficiency)
        return GameRules.grownRadius(predator: once, prey: missedFishMeal, efficiency: level.effectiveAbsorptionEfficiency)
    }

    /// A last meal that takes a fish of `you` just past `rival` (at least 2% bigger), within sensible meal sizes.
    static func lastMeal(you: CGFloat, rival: CGFloat) -> CGFloat {
        let needed = ((rival * 1.02) * (rival * 1.02) - you * you) / level.effectiveAbsorptionEfficiency
        return min(you * 0.85, max(8, needed > 0 ? needed.squareRoot() : 8))
    }

    /// How a beat's fish look: the missed fish is purple and spotted, so you know it again when it comes back.
    static let missedStyle = FishStyle(body: SKColor(red: 0.61, green: 0.36, blue: 0.90, alpha: 1),
                                       accent: SKColor(red: 0.85, green: 0.72, blue: 1.00, alpha: 1),
                                       pattern: .spots, tail: .fork, eyeScale: 1.1, hasDorsalFin: true)
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

    /// Swims straight at you along `share`, from just off screen to behind you, crossing you at `crossing` seconds.
    static func headOn(share: CGFloat, crossing: CGFloat) -> TutorialPath {
        let start: CGFloat = 0.78, end: CGFloat = -0.45
        return TutorialPath(points: [(0, start, share), (crossing * (start - end) / start, end, share)])
    }
}
