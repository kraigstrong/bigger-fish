import CoreGraphics
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
        // Missed one: the next makes you big enough on its own.
        #expect(GameRules.playerEncounter(A.grow(once, eating: A.wallMeal(you: once, wall: wall, meals: 1)), wall) == .firstEatsSecond)
        // At the tutorial's zoom, three wall fish leave no gap anywhere you can swim.
        let water = PlayerTimeline.waterBounds(zoom: T.tutorialZoom)
        let heights = A.wallHeights(you: you, wall: wall, bottom: water.bottom, top: water.top)
        #expect(heights.count == 3)
        #expect(A.wallBlocks(you: you, wall: wall, heights: heights, bottom: water.bottom, top: water.top))
    }

    @Test func theMissedFishCatchesItsMealsAsItPassesYou() {
        typealias T = GameTuning
        let leads = ArcadeTutorial.missedMealLeads
        // Its meals set off first, slower, and it has caught the first before it reaches the second.
        #expect(leads.allSatisfy { $0 > 0 && $0 < T.tutorialMissedFishSets })
        #expect(T.tutorialMissedMealSpeed < T.tutorialMissedFishSpeed)
        let catches = T.tutorialMissedCatches
        #expect(catches[0] > 0 && catches[1] < 0 && catches[1] > -0.3, "one as it passes you, one just behind, on screen")
        let between = (catches[0] - catches[1]) / T.tutorialMissedFishSpeed / T.tutorialPace
        #expect(between > 0.55, "time to swallow the first meal before the second: \(between) s")
        // Everything that swims at you does so faster than you swim, so it never looks to swim backwards.
        let you = 1 / 3.2
        #expect([T.tutorialMissedMealSpeed, T.tutorialMissedFishSpeed, T.tutorialWallSpeed].allSatisfy { $0 > you })
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
