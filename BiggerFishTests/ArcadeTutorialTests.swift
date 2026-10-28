import CoreGraphics
import FishKit
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// Adventure's tutorial teaches the race: the sizes have to tell that story, and a player has to be able to play it
/// through quickly. The Open Water's teaches eating, avoiding, and pearls; each plays once, for someone new to it.
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
        #expect(heights.count == 3)
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
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
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
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
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
        // The wall stays side by side as it comes, so there's no slipping past one fish and then ducking the next.
        for _ in 0..<12 {
            let lead = beat.wall.map { scene.debugTutorialPlace($0).ahead }
            #expect(lead.max()! - lead.min()! < 0.002, "the wall's fish are \(lead) screens ahead")
            scene.debugAdvance(seconds: 0.5)
            beat = scene.debugWallBeat
            if beat.wall.count < 3 { break }
        }
        for (meal, swim) in zip(beat.meals, GameTuning.tutorialWallMeals) {
            #expect(abs(scene.debugTutorialPlace(meal).share - swim.home) <= swim.wander + 0.001)
        }
        withExtendedLifetime(view) {}
    }

    /// Miss a meal and the wall eats you; the card offers just Retry, which starts the wall again at once.
    @Test func missingAMealGetsYouEatenAndRetryStartsTheWallAgain() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
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

    /// Through the wall, the other two (smaller than you now) bolt ahead, one further than the other, and tire: you
    /// catch them both and you're the last fish swimming, which ends it, as it ends a level.
    @Test func throughTheWallYouBecomeTheLastFishSwimming() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        var frames = 0, ahead: [CGFloat] = []
        let run = scene.debugPlayTutorial(from: .eatEnough) {
            guard scene.debugTutorialBeat == .lastFish else { return }
            frames += 1
            // A couple of seconds in: both out ahead of you, on screen, strung out.
            if frames == 140 { ahead = scene.debugWallBeat.wall.filter { $0.state == .swimming }.map { scene.debugTutorialPlace($0).ahead } }
        }
        #expect(run.finished && run.beats.map(\.beat) == [.eatEnough, .lastFish], "beats: \(run.beats.map(\.beat))")
        #expect(ahead.count == 2 && ahead.allSatisfy { $0 > 0.08 && $0 < 0.7 }, "ahead: \(ahead)")
        #expect((ahead.max() ?? 0) - (ahead.min() ?? 0) > 0.08, "strung out: \(ahead)")
        #expect(scene.debugWallBeat.wall.isEmpty && scene.debugWallBeat.meals.isEmpty)
        withExtendedLifetime(view) {}
    }

    /// One of the last two that gets past you comes round again from off screen ahead, swimming away, so it can still
    /// be caught (it's never left behind for good, and it doesn't pop up in view).
    @Test func aLastFishThatGetsPastYouComesRoundAgain() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        var last: [Int: CGFloat] = [:], cameRound: [CGFloat] = []
        let run = scene.debugPlayTutorial(limit: 45, from: .eatEnough, letsTheLastFishGo: true) {
            guard scene.debugTutorialBeat == .lastFish else { return }
            for f in scene.debugWallBeat.wall where f.state == .swimming {
                let ahead = scene.debugTutorialPlace(f).ahead
                if let before = last[f.id], before < -0.3 && ahead > 0.3 { cameRound.append(ahead) }
                last[f.id] = ahead
            }
        }
        #expect(!run.finished && !cameRound.isEmpty, "came round at \(cameRound)")
        #expect(cameRound.allSatisfy { $0 > 0.75 }, "it should come back off screen: \(cameRound)")
        withExtendedLifetime(view) {}
    }

    /// The meals wander, but gently: a first-time player who's slow on the controls still catches both.
    @Test func aSlowPlayerStillGetsThroughTheWall() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        let run = scene.debugPlayTutorial(from: .eatEnough, lag: 0.5)
        #expect(run.finished && scene.debugWallBeat.meals.isEmpty, "after \(run.seconds) s")
        withExtendedLifetime(view) {}
    }

    /// The fish that got away swims smoothly round to you while you eat your meal and catch it: eating doesn't stop
    /// it in its tracks and then snap it back along its path.
    @Test func theMissedFishSwimsSmoothlyWhileYouEat() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        // Its place on screen in screen widths, across and up.
        let tall = (PlayerTimeline.waterBounds(zoom: GameTuning.tutorialZoom).top - PlayerTimeline.waterBounds(zoom: GameTuning.tutorialZoom).bottom)
            / GameTuning.playfieldSize.width
        var last: (x: CGFloat, y: CGFloat)?, biggest: CGFloat = 0
        let run = scene.debugPlayTutorial(from: .missedFishEats) {
            guard scene.debugTutorialBeat == .catchItBack, let rival = scene.debugMissedFish, rival.state == .swimming else { last = nil; return }
            let place = scene.debugTutorialPlace(rival)
            // Only while it's on screen (coming round, it jumps from behind you to ahead, out of sight).
            guard place.ahead > -0.35 && place.ahead < 0.75 else { last = nil; return }
            let now = (x: place.ahead, y: place.share * tall)
            if let last { biggest = max(biggest, hypot(now.x - last.x, now.y - last.y)) }
            last = now
        }
        #expect(run.finished)
        // It comes at you at about 0.007 screens a frame; a snap back along its path is far more.
        #expect(biggest < 0.015, "it moved \(biggest) screens in one frame")
        withExtendedLifetime(view) {}
    }

    /// "Hold anywhere to rise" wants a clear rise, not a trip to the top: one short hold does it.
    @Test func aShortHoldIsEnoughToRise() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
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
            let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            let run = scene.debugPlayTutorial(eatenOn: beat)
            #expect(!run.finished && scene.debugTutorialBeat == beat, "\(beat): reached \(scene.debugTutorialBeat)")
            // You swim about 3.4 points a frame; being carried into a fish is no faster than that.
            #expect(scene.debugCaughtStep > 0 && scene.debugCaughtStep < 8, "\(beat): jumped \(scene.debugCaughtStep) points in a frame")
            withExtendedLifetime(view) {}
        }
    }

    /// A fish whose scripted path ends mid-meal finishes eating before it leaves; and a fish taken out mid-swallow lets
    /// the other go. Before, the swallow was orphaned: its prey waited forever, and if that was you, the run never ended.
    @Test func aFishLeavingMidSwallowLeavesNothingStuck() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStartTutorial(at: .holdToRise)
        let left = scene.debugLeavingMidSwallow()
        #expect(left.stayedToEat && left.leftAfter && left.youSwimOn, "\(left)")
        withExtendedLifetime(view) {}
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
        #expect(new.needsTutorial(.adventure))
        new.sawTutorial(.adventure)
        #expect(!new.needsTutorial(.adventure) && new.save.hasSeenTutorial == true)
        // A save from before the tutorial: someone who has cleared a level skips it; someone who hasn't sees it.
        #expect(!progress(#"{"clearedLevels":["shallow-reef.1"],"bestTimes":{},"hasSeenJellyLesson":false}"#).needsTutorial(.adventure))
        #expect(progress(#"{"clearedLevels":[],"bestTimes":{},"hasSeenJellyLesson":false}"#).needsTutorial(.adventure))
    }

    @Test func aPlayerFinishesItInUnderAMinute() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        let run = scene.debugPlayTutorial()
        print("TUTORIAL finished=\(run.finished) seconds=\(String(format: "%.1f", run.seconds)) beats=\(run.beats.map { "\($0.beat)@\(String(format: "%.1f", $0.at))" })")
        #expect(run.finished, "beats reached: \(run.beats.map { "\($0.beat) at \(String(format: "%.1f", $0.at))" })")
        #expect(run.beats.map(\.beat) == ArcadeTutorial.Course.adventure.beats)
        #expect(run.seconds < 60)
        withExtendedLifetime(view) {}
    }

    /// The last beat says how a level is won, and counts down the fish still to eat under it.
    @Test func theLastBeatCountsTheFishLeft() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        var shown: [String] = [], line: String?
        let run = scene.debugPlayTutorial(from: .eatEnough) {
            guard scene.debugTutorialBeat == .lastFish else { return }
            let caption = scene.debugTutorialCaption
            line = caption.line
            if let left = caption.fishLeft, shown.last != left { shown.append(left) }
        }
        #expect(run.finished)
        #expect(line == "Eat every fish to win" && line == ArcadeHome.winRule)
        #expect(shown == ["2 fish left", "Last fish!"], "shown: \(shown)")
        withExtendedLifetime(view) {}
    }

    /// The Open Water's: rise and fall, eat a smaller fish, avoid a bigger one, and take the pearl by the next big fish,
    /// with the fish and pearls counted at the top as in a run. Quick, and it never keeps the pearl.
    @Test func theOpenWatersTutorialEndsOnAPearl() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .openWater)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        var pearled = 0
        scene.onPearl = { pearled += 1 }
        let run = scene.debugPlayTutorial()
        print("OPEN WATER TUTORIAL finished=\(run.finished) seconds=\(String(format: "%.1f", run.seconds))")
        #expect(run.finished, "beats reached: \(run.beats.map { "\($0.beat) at \(String(format: "%.1f", $0.at))" })")
        #expect(run.beats.map(\.beat) == ArcadeTutorial.Course.openWater.beats)
        #expect(run.seconds < 35)
        #expect(scene.debugTutorialPearls.taken == 1 && scene.debugTutorialPearls.inWater.isEmpty)
        let counts = scene.debugCounts
        #expect(counts.fish == "1" && counts.pearls == "1")
        #expect(pearled == 0)
        withExtendedLifetime(view) {}
    }

    /// The pearl's big fish swims beside it, not through it: going straight for the pearl never meets the fish.
    @Test func thePearlsBigFishLeavesRoomToTakeIt() {
        typealias T = GameTuning
        let water = T.playfieldSize.height - T.waterTopMargin - T.waterBottomMargin
        let you = ArcadeTutorial.radius(startingAt: .gatherPearls)
        let reach = (you + T.tutorialBigFish) * T.collisionScale
        // Anywhere you can touch the pearl from, with the fish anywhere it wanders.
        let gap = (T.tutorialPearlShare - T.tutorialPearlGuard.home - T.tutorialPearlGuard.wander) * water - you - T.openWaterPearlRadius
        #expect(gap > reach, "gap \(gap), reach \(reach)")
        #expect(GameRules.playerEncounter(you, T.tutorialBigFish) == .secondEatsFirst)
    }

    /// Miss the pearl and another comes, the other way up, with its own big fish; you're never stuck.
    @Test func aMissedPearlComesAgainTheOtherWayUp() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .openWater)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        var heights: [Bool] = []
        let run = scene.debugPlayTutorial(limit: 14, from: .gatherPearls, missesThePearl: true) {
            guard let pearl = scene.debugTutorialPearls.inWater.first else { return }
            let high = pearl.position.y > GameTuning.playfieldSize.height / 2
            if heights.last != high { heights.append(high) }
        }
        #expect(!run.finished && scene.debugResultTitles.isEmpty, "eaten or done after \(run.seconds) s")
        #expect(heights.count >= 3 && heights.prefix(2) == [true, false], "pearls: \(heights)")
        #expect(scene.debugTutorialPearls.taken == 0)
        withExtendedLifetime(view) {}
    }

    /// Eaten by the pearl's big fish: Retry starts the pearl again at once.
    @Test func beingEatenByThePearlsFishTriesThePearlAgain() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .openWater)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        let run = scene.debugPlayTutorial(from: .gatherPearls, eatenOn: .gatherPearls)
        #expect(!run.finished && scene.debugResultTitles == ["Retry"])
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugTutorialBeat == .gatherPearls && scene.debugTutorialPearls.inWater.count == 1)
        #expect(scene.debugCounts.fish == "1" && scene.debugCounts.pearls == "0")
        #expect(scene.debugResultTitles.isEmpty)
        withExtendedLifetime(view) {}
    }

    /// A new player's first screen is just the first beat's line, and the finger that shows how: no goal over it.
    @Test func eachTutorialOpensOnHoldToRise() {
        for course in [ArcadeTutorial.Course.adventure, .openWater] {
            let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: course)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            #expect(scene.debugTutorialBeat == .holdToRise && scene.debugPhase == .ready)
            #expect(scene.debugTutorialCaption.line == "Hold anywhere to rise", "\(course)")
            #expect(scene.debugCardTexts.isEmpty, "\(course): \(scene.debugCardTexts)")
            withExtendedLifetime(view) {}
        }
    }

    /// Someone who learned to rise and fall in the other tutorial (or a level, or a run) starts at the first meal, after
    /// a tap, with Tap to start under its line until then.
    @Test func aPlayerWhoKnowsTheControlsStartsAtTheFirstMeal() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .openWater, knowsControls: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        #expect(scene.debugTutorialBeat == .eatSmaller && scene.debugPhase == .ready)
        #expect(scene.debugCardTexts == ["Tap to start"])
        let run = scene.debugPlayTutorial()
        #expect(run.finished && run.beats.map(\.beat) == [.eatSmaller, .dodgeBigger, .gatherPearls])
        withExtendedLifetime(view) {}
    }

    /// Each plays the first time its part of the home screen is opened, once, and only for someone new to it. Rising
    /// and falling, once learned anywhere, aren't taught again.
    @Test func eachTutorialIsForSomeoneNewToIt() {
        func progress(_ json: String?) -> ArcadeProgress {
            let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
            if let json { defaults.set(Data(json.utf8), forKey: ArcadeProgress.key) }
            return ArcadeProgress(defaults: defaults)
        }
        let new = progress(nil)
        #expect(ArcadeTutorial.Course.allCases.allSatisfy(new.needsTutorial) && !new.knowsControls)
        new.sawTutorial(.openWater)
        #expect(!new.needsTutorial(.openWater) && new.needsTutorial(.adventure) && new.needsTutorial(.shop) && new.knowsControls)
        new.sawTutorial(.shop)
        #expect(!new.needsTutorial(.shop) && new.save.hasSeenShopTutorial == true && new.save.hasSeenOpenWaterTutorial == true)
        // A 1.1 beta save: runs and pearls, so no Open Water tutorial; a look bought, so no Shop's; no level cleared.
        let tester = progress(#"{"clearedLevels":[],"bestTimes":{},"hasSeenJellyLesson":false,"hasSeenTutorial":true,"openWaterBest":12,"pearlsEarned":{"a":30},"ownedLooks":["hat.beanie"]}"#)
        #expect(!tester.needsTutorial(.adventure) && !tester.needsTutorial(.openWater) && !tester.needsTutorial(.shop))
        // Pearls without a best (a run quit early) count too; looked but bought nothing: the Shop's still plays.
        let pearls = progress(#"{"clearedLevels":["shallow-reef.1"],"bestTimes":{},"hasSeenJellyLesson":false,"pearlsEarned":{"a":1}}"#)
        #expect(!pearls.needsTutorial(.openWater) && pearls.needsTutorial(.shop) && pearls.knowsControls)
    }
}
