import CoreGraphics
import FishKit
import SpriteKit

/// Bigger Fish's tutorials, one for each part of the home screen, each the first time you open it (Kraig, 2026-10-27:
/// "break out into 3 separate tutorials"). Adventure's teaches the race at the heart of a level and how a level is won.
/// Hold to rise and let go to fall, as Math Reef teaches it; eat smaller fish, steer clear of bigger ones, and eat on
/// your first pass: a fish you miss keeps eating, swims on round the reef, and comes back bigger. Then the gates every
/// level has: eat enough to get through, played like a level, and how a level is won: eat every fish. The Open Water's
/// is short: eat smaller, avoid bigger, and gather pearls. The Shop's is a few words and arrows over the shop
/// (`ShopHints`). The early fish swim scripted paths, but every bite is the game's own (the same collisions, swallows,
/// and growth as a level), so you watch a missed fish's real size change.
enum ArcadeTutorial {
    /// A tutorial, for one part of the home screen.
    enum Course: String, CaseIterable {
        case adventure
        case openWater
        /// Played over the shop, not in the water (`ShopHints`).
        case shop

        /// Its beats, in order. Rising and falling come first, unless you've learned them already (`opening`).
        var beats: [Beat] {
            switch self {
            case .adventure: [.holdToRise, .letGoToFall, .eatSmaller, .dodgeBigger, .missedFishEats, .catchItBack, .eatEnough, .lastFish]
            case .openWater: [.holdToRise, .letGoToFall, .eatSmaller, .dodgeBigger, .gatherPearls]
            case .shop: []
            }
        }

        /// The beat it opens with: its first meal for a player who has already learned to rise and fall (in the other
        /// tutorial, a level, or a run).
        func opening(knowsControls: Bool) -> Beat { knowsControls ? .eatSmaller : .holdToRise }

        func beat(after beat: Beat) -> Beat? {
            guard let index = beats.firstIndex(of: beat), index + 1 < beats.count else { return nil }
            return beats[index + 1]
        }

        /// What the way to play is about, in the middle of the screen until your first touch: Adventure's says it as its
        /// card on the home screen does.
        var goal: String {
            switch self {
            case .adventure: ArcadeHome.winRule
            case .openWater, .shop: "How far can you get?"
            }
        }

        /// The line it ends on, before it leaves.
        var finale: String {
            switch self {
            case .adventure: "You ate every fish. You win!"
            case .openWater, .shop: "Now see how far you can get!"
            }
        }

        /// Its button in Settings' How to play: the name and symbol of its part of the home screen.
        var title: String {
            switch self {
            case .adventure: "Adventure"
            case .openWater: "Open Water"
            case .shop: "Shop"
            }
        }
        var symbol: String {
            switch self {
            case .adventure: "map.fill"
            case .openWater: "infinity"
            case .shop: "bag.fill"
            }
        }
    }

    enum Beat: Int, CaseIterable {
        /// A finger presses open water: touching anywhere lifts you (your first touch starts the tutorial).
        case holdToRise
        /// The finger lifts off: let go and you sink.
        case letGoToFall
        /// One small glowing fish ahead.
        case eatSmaller
        /// A bigger fish swims at you: go around it.
        case dodgeBigger
        /// A fish you pass eats two little ones as it goes by, and swims on.
        case missedFishEats
        /// One more glowing meal, and the fish that outgrew you comes round again: yours.
        case catchItBack
        /// Played like a level: two meals swimming freely, then a wall of three fish a little bigger than you swimming
        /// at you. Eat both and you eat your way through; miss one and the wall eats you (one tap tries it again).
        case eatEnough
        /// Through the wall, the other two (smaller than you now) bolt ahead and tire: catch them both, and you've eaten
        /// every fish. A level is won the same way.
        case lastFish
        /// The Open Water's: a pearl ahead, with a bigger fish beside it as pearls have in a run. Touch it to take it.
        case gatherPearls

        /// The one short line shown with the beat.
        var caption: String {
            switch self {
            case .holdToRise: "Hold anywhere to rise"
            case .letGoToFall: "Let go to fall"
            case .eatSmaller: "Eat smaller fish"
            case .dodgeBigger: "Avoid bigger fish"
            case .missedFishEats: "Fish you miss keep eating"
            case .catchItBack: "Grow, then catch it"
            case .eatEnough: "Eat enough to get through"
            case .lastFish: ArcadeHome.winRule
            case .gatherPearls: "Gather pearls"
            }
        }

        /// Where a retry starts after being eaten: the race's two beats go together, and so do the wall's.
        var checkpoint: Beat {
            switch self {
            case .catchItBack: .missedFishEats
            case .lastFish: .eatEnough
            default: self
            }
        }
    }

    /// Under the last beat's line, the fish still to eat; an Adventure level counts down the same way at the top.
    static func fishLeft(_ count: Int) -> String { count == 1 ? "Last fish!" : "\(count) fish left" }

    /// Once the pearl's taken, before the Open Water's tutorial ends: what pearls are for.
    static let pearlsAreFor = "Spend pearls in the Shop"

    /// Your radius at the start of a beat, eating what the beats before it fed you.
    static func radius(startingAt beat: Beat) -> CGFloat {
        let base = GameTuning.baseRadius
        let afterFirst = grow(base, eating: GameTuning.tutorialFirstMeal)
        switch beat {
        case .holdToRise, .letGoToFall, .eatSmaller: return base
        case .dodgeBigger, .missedFishEats, .catchItBack, .gatherPearls: return afterFirst
        case .eatEnough, .lastFish:
            let afterLast = grow(afterFirst, eating: lastMeal(you: afterFirst, rival: missedFishGrown))
            return grow(afterLast, eating: missedFishGrown)
        }
    }

    /// Fish you've eaten at the start of a beat (the Open Water's tutorial counts them, as a run does).
    static func meals(before beat: Beat) -> Int {
        switch beat {
        case .holdToRise, .letGoToFall, .eatSmaller: 0
        case .dodgeBigger, .missedFishEats, .catchItBack, .gatherPearls: 1
        case .eatEnough: 3
        case .lastFish: 6
        }
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

    /// Where the wall's three fish swim (world heights, bottom to top) for water from `bottom` to `top`: one in the
    /// middle, the other two `GameTuning.tutorialWallSpread` of the water apart (two thirds spaces all three
    /// evenly), still too close for you to slip between.
    static func wallHeights(bottom: CGFloat, top: CGFloat) -> [CGFloat] {
        let middle = (bottom + top) / 2, half = (top - bottom) * GameTuning.tutorialWallSpread / 2
        return [middle - half, middle, middle + half]
    }

    /// Whether a fish of `you` can't get past fish of `wall` at `heights` anywhere it can swim, with each wall fish
    /// anywhere within `bob` points of its height.
    static func wallBlocks(you: CGFloat, wall: CGFloat, heights: [CGFloat], bottom: CGFloat, top: CGFloat, bob: CGFloat = 0) -> Bool {
        let reach = (you + wall) * GameTuning.collisionScale - bob
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

/// How a fish in the last beat swims, like one in a level rather than along a path: on at its own pace (a little
/// faster and slower as it goes), wandering up and down near its height, facing the way it swims.
struct TutorialSwim {
    /// Where it starts, in screens ahead of you.
    var ahead: CGFloat
    /// The height it keeps near (share of the water: 0 the bottom, 1 the top), and how far either side it wanders.
    var home: CGFloat
    var wander: CGFloat
    /// -1 swims at you, 1 away from you.
    var heading: CGFloat
    /// Points a second.
    var speed: CGFloat
    /// A wall fish holds its height instead of wandering, bobbing this many points either side.
    var bob: CGFloat = 0
    /// Bolting: this many points a second until `dashUntil` (sim seconds), easing back to `speed` after.
    var dashSpeed: CGFloat = 0
    var dashUntil: CGFloat = 0
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
