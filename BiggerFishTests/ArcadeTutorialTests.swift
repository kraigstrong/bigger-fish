import CoreGraphics
import FishKit
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The first-launch tutorial teaches the race: the sizes have to tell that story, and a player has to be able to
/// play it through quickly.
@MainActor
struct ArcadeTutorialTests {
    @Test func sizesTellTheRace() {
        typealias A = ArcadeTutorial
        typealias T = GameTuning
        let efficiency = T.tutorialLevel.effectiveAbsorptionEfficiency
        let afterFirst = A.radius(startingAt: .dodgeBigger)
        #expect(A.radius(startingAt: .eatSmaller) == T.baseRadius)
        // You can eat the first meal, not the big fish, and the missed fish while it passes you.
        #expect(GameRules.playerEncounter(T.baseRadius, T.tutorialFirstMeal) == .firstEatsSecond)
        #expect(GameRules.playerEncounter(afterFirst, T.tutorialBigFish) == .secondEatsFirst)
        #expect(GameRules.playerEncounter(afterFirst, T.tutorialMissedFish) == .firstEatsSecond)
        // It eats its two meals (they're smaller, not a near tie) and outgrows you.
        #expect(GameRules.encounter(T.tutorialMissedFish, T.tutorialMissedFishMeal) == .firstEatsSecond)
        #expect(GameRules.playerEncounter(afterFirst, A.missedFishGrown) == .secondEatsFirst)
        // One more meal and it's yours again, by the margin the tuning asks for.
        let last = A.lastMeal(you: afterFirst, rival: A.missedFishGrown)
        #expect(GameRules.playerEncounter(afterFirst, last) == .firstEatsSecond)
        let grown = GameRules.grownRadius(predator: afterFirst, prey: last, efficiency: efficiency)
        #expect(GameRules.playerEncounter(grown, A.missedFishGrown) == .firstEatsSecond)
        #expect(abs(grown / A.missedFishGrown - T.tutorialCatchMargin) < 0.001)
        // The sizes the tuning comment describes.
        #expect(abs(afterFirst - 18.4) < 0.1 && abs(A.missedFishGrown - 20.7) < 0.1)
        #expect(abs(last - 14.2) < 0.1 && abs(grown - 22.4) < 0.1)
    }

    @Test func theWallTakesTwoMealsAndBlocksTheWater() {
        typealias A = ArcadeTutorial
        typealias T = GameTuning
        let you = A.radius(startingAt: .eatEnough)
        let wall = A.wallFish(you: you)
        // You're bigger than every fish so far, and a wall fish is a little bigger than you.
        #expect(you > A.missedFishGrown && GameRules.playerEncounter(you, wall) == .secondEatsFirst)
        let meal = A.wallMeal(you: you, wall: wall)
        #expect(GameRules.playerEncounter(you, meal) == .firstEatsSecond)
        let once = A.grow(you, eating: meal), twice = A.grow(once, eating: meal)
        #expect(GameRules.playerEncounter(once, wall) == .secondEatsFirst, "one meal shouldn't be enough")
        #expect(GameRules.playerEncounter(twice, wall) == .firstEatsSecond, "two meals should be")
        #expect(abs(twice / wall - T.tutorialWallMargin) < 0.001)
        // At the tutorial's zoom, three wall fish leave no gap anywhere you can swim, however they bob: as you are when
        // it comes, after one meal, and when you're big enough to eat through.
        let water = PlayerTimeline.waterBounds(zoom: T.tutorialZoom)
        let heights = A.wallHeights(bottom: water.bottom, top: water.top)
        #expect(heights.count == 3 && T.tutorialWallAhead.count == 3)
        for size in [you, once, twice] {
            #expect(A.wallBlocks(you: size, wall: wall, heights: heights, bottom: water.bottom, top: water.top, bob: T.tutorialWallBob),
                    "a fish of \(size)")
        }
        // Spread out, with clear water between them.
        #expect(heights[1] - heights[0] > 2 * wall * 1.6)
    }

    @Test func theMissedFishCatchesItsMealsAsItPassesYou() {
        typealias T = GameTuning
        let leads = ArcadeTutorial.missedMealLeads
        // Its meals set off first, slower, and it has caught the first before it reaches the second.
        #expect(leads.allSatisfy { $0 > 0 && $0 < T.tutorialMissedFishSets })
        #expect(T.tutorialMissedMealSpeed < T.tutorialMissedFishSpeed)
        let catches = T.tutorialMissedCatches
        // Both well on screen and ahead of you (you're 0.3 of a screen from its left edge, and it starts 0.7 ahead).
        #expect(catches[0] > catches[1] && catches.allSatisfy { $0 > 0 && $0 < 0.6 })
        let between = (catches[0] - catches[1]) / T.tutorialMissedFishSpeed / T.tutorialPace
        #expect(between > 0.55, "time to swallow the first meal before the second: \(between) s")
        // It's done eating and growing, with a moment to see it at its new size, before it swims off the left edge.
        let meal = T.tutorialMissedFishMeal, grown = ArcadeTutorial.grow(T.tutorialMissedFish, eating: meal)
        let bite = SwallowTiming.duration(sizeRatio: meal / grown, curve: T.swallowDurationCurve) + T.growDuration
        let onScreen = (catches[1] + T.playerScreenX) / T.tutorialMissedFishSpeed / T.tutorialPace
        #expect(onScreen > bite + 0.6, "after its second bite it's on screen \(onScreen) s, and takes \(bite) s to finish growing")
        // Everything that swims at you does so faster than you swim, so it never looks to swim backwards.
        let you = 1 / 3.2
        #expect([T.tutorialMissedMealSpeed, T.tutorialMissedFishSpeed].allSatisfy { $0 > you })
    }

    @Test func youCantEatTheMissedFishsMealsWhileItEatsThem() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        // Even going straight for its meals, you hold your height while it eats, so it eats both and grows.
        let run = scene.debugPlayTutorial(greedy: true)
        #expect(run.finished)
        let grew = scene.debugMissedFishGrewTo ?? 0
        #expect(abs(grew - ArcadeTutorial.missedFishGrown) < 0.5, "it grew to \(grew)")
        withExtendedLifetime(view) {}
    }

    /// The wall plays like a level: two meals and the wall swim freely (nothing scripted), coming in from off screen
    /// ahead, and the meals wander up and down rather than run on rails.
    @Test func theWallPlaysLikeALevel() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStartTutorial(at: .eatEnough)
        var beat = scene.debugWallBeat
        #expect(beat.meals.count == 2 && beat.wall.count == 3 && beat.scripted == 0)
        // Everything starts off screen ahead (you're 0.3 of a screen from the left edge), the meals before the wall.
        let starts = (beat.meals + beat.wall).map { scene.debugTutorialPlace($0).ahead }
        #expect(starts.allSatisfy { $0 > 0.75 }, "starts: \(starts)")
        #expect(starts[1] < starts[2...].min()!)
        // The first meal swims at you, the second away (you chase it), and the wall at you.
        #expect(beat.meals.map(\.facing) == [-1, 1] && beat.wall.allSatisfy { $0.facing == -1 })
        let heights = beat.meals.map { scene.debugTutorialPlace($0).share }
        scene.debugAdvance(seconds: 2.5)
        beat = scene.debugWallBeat
        let wandered = zip(beat.meals.map { scene.debugTutorialPlace($0).share }, heights).map { abs($0 - $1) }
        #expect(wandered.allSatisfy { $0 > 0.01 }, "the meals should wander: \(wandered)")
        for (meal, swim) in zip(beat.meals, GameTuning.tutorialWallMeals) {
            #expect(abs(scene.debugTutorialPlace(meal).share - swim.home) <= swim.wander + 0.001)
        }
        withExtendedLifetime(view) {}
    }

    /// Miss a meal and the wall eats you; the card offers just Retry, which starts the wall again at once.
    @Test func missingAMealGetsYouEatenAndRetryStartsTheWallAgain() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        let run = scene.debugPlayTutorial(missesAWallMeal: true, from: .eatEnough)
        #expect(!run.finished && run.seconds < 20, "lasted \(run.seconds) s")
        #expect(scene.debugResultTitles == ["Retry"])
        scene.debugTapResult(.tryAgain)
        let beat = scene.debugWallBeat
        #expect(scene.debugTutorialBeat == .eatEnough && beat.meals.count == 2 && beat.wall.count == 3)
        #expect(abs(scene.debugPlayerRadius - ArcadeTutorial.radius(startingAt: .eatEnough)) < 0.001)
        // Playing straight in: no card, no first tap.
        #expect(scene.debugResultTitles.isEmpty)
        // And eating both gets you through.
        #expect(scene.debugPlayTutorial(from: .eatEnough).finished)
        withExtendedLifetime(view) {}
    }

    /// The meals wander, but gently: a first-time player who's slow on the controls still catches both.
    @Test func aSlowPlayerStillGetsThroughTheWall() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        let run = scene.debugPlayTutorial(from: .eatEnough, lag: 0.5)
        #expect(run.finished && scene.debugWallBeat.meals.isEmpty, "after \(run.seconds) s")
        withExtendedLifetime(view) {}
    }

    /// "Hold anywhere to rise" wants a clear rise, not a trip to the top: one short hold does it.
    @Test func aShortHoldIsEnoughToRise() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStartTutorial(at: .holdToRise)
        let start = scene.debugPlayerShare
        scene.debugHold(true)
        var highest = start, held: CGFloat = 0
        while scene.debugTutorialBeat == .holdToRise && held < 3 {
            scene.debugAdvance(seconds: 1.0 / 60)
            held += 1.0 / 60
            highest = max(highest, scene.debugPlayerShare)
        }
        #expect(scene.debugTutorialBeat == .letGoToFall)
        #expect(highest < 0.8 && held < 1.2, "rose from \(start) to \(highest) over \(held) s")
        withExtendedLifetime(view) {}
    }

    /// Caught by a fish on a scripted path, you're carried smoothly into it: the screen doesn't race ahead. (A path is
    /// measured from you, and you're carried along by the fish that caught you, so each chased the other ahead.)
    @Test func beingCaughtDoesntSweepTheScreenAhead() {
        for beat in [ArcadeTutorial.Beat.dodgeBigger, .catchItBack] {
            let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            let run = scene.debugPlayTutorial(eatenOn: beat)
            #expect(!run.finished && scene.debugTutorialBeat == beat, "\(beat): reached \(scene.debugTutorialBeat)")
            // You swim about 3.4 points a frame; being carried into a fish is no faster than that.
            #expect(scene.debugCaughtStep > 0 && scene.debugCaughtStep < 8, "\(beat): jumped \(scene.debugCaughtStep) points in a frame")
            withExtendedLifetime(view) {}
        }
    }

    @Test func pathsAreMeasuredFromYou() {
        let path = TutorialPath.headOn(share: 0.6, crossing: 1.6)
        #expect(path.at(0) == (0.78, 0.6))
        #expect(abs(path.at(1.6).ahead) < 0.001)
        #expect(path.at(99).ahead == -0.45 && path.at(99).share == 0.6)
        let turn = TutorialPath(points: [(0, 0, 0.2), (1, 1, 0.4)])
        #expect(abs(turn.at(0.5).ahead - 0.5) < 0.0001 && abs(turn.at(0.5).share - 0.3) < 0.0001)
    }

    @Test func onlyNewPlayersSeeItOnce() throws {
        func progress(_ json: String?) -> ArcadeProgress {
            let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
            if let json { defaults.set(Data(json.utf8), forKey: ArcadeProgress.key) }
            return ArcadeProgress(defaults: defaults)
        }
        let new = progress(nil)
        #expect(new.needsTutorial)
        new.sawTutorial()
        #expect(!new.needsTutorial && new.save.hasSeenTutorial == true)
        // A save from before the tutorial: someone who has cleared a level skips it; someone who hasn't sees it.
        #expect(!progress(#"{"clearedLevels":["shallow-reef.1"],"bestTimes":{},"hasSeenJellyLesson":false}"#).needsTutorial)
        #expect(progress(#"{"clearedLevels":[],"bestTimes":{},"hasSeenJellyLesson":false}"#).needsTutorial)
    }

    @Test func aPlayerFinishesItInUnderAMinute() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        let run = scene.debugPlayTutorial()
        print("TUTORIAL finished=\(run.finished) seconds=\(String(format: "%.1f", run.seconds)) beats=\(run.beats.map { "\($0.beat)@\(String(format: "%.1f", $0.at))" })")
        #expect(run.finished, "beats reached: \(run.beats.map { "\($0.beat) at \(String(format: "%.1f", $0.at))" })")
        #expect(run.beats.map(\.beat) == ArcadeTutorial.Beat.allCases)
        #expect(run.seconds < 60)
        withExtendedLifetime(view) {}
    }
}
