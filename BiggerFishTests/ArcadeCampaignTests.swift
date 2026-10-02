import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

struct ArcadeCampaignTests {
    private func fresh() -> (ArcadeProgress, UserDefaults) {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        return (ArcadeProgress(defaults: defaults), defaults)
    }

    @Test func bothWorldsStartAtLevelOne() {
        let (progress, _) = fresh()
        for world in ArcadeWorld.allCases {
            #expect(progress.isOpen(world, 0))
            #expect(!progress.isOpen(world, 1))
            #expect(!progress.isOpen(world, -1))
            #expect(!progress.isOpen(world, 5))
            #expect(world.levels.count == 5)
        }
    }

    @Test func clearUnlocksOnlyTheNextLevelAndPersists() {
        let (progress, defaults) = fresh()
        progress.clear(.jellyBloom, 0, seconds: 42)
        let restored = ArcadeProgress(defaults: defaults)
        #expect(restored.isCleared(.jellyBloom, 0))
        #expect(restored.isOpen(.jellyBloom, 1))
        #expect(!restored.isOpen(.jellyBloom, 2))
        #expect(!restored.isOpen(.shallowReef, 1))
        #expect(restored.nextLevel(in: .jellyBloom) == 1)
    }

    @Test func replayKeepsTheFastestTimeAndCompletion() {
        let (progress, _) = fresh()
        progress.clear(.shallowReef, 0, seconds: 50)
        progress.clear(.shallowReef, 0, seconds: 70)
        #expect(progress.save.bestTimes["shallow-reef.1"] == 50)
        progress.clear(.shallowReef, 0, seconds: 35)
        #expect(progress.save.bestTimes["shallow-reef.1"] == 35)
        #expect(progress.save.clearedLevels.count == 1)
    }

    @Test func aCompletedWorldRemainsReplayable() {
        let (progress, _) = fresh()
        for index in 0..<5 { progress.clear(.jellyBloom, index, seconds: 30) }
        #expect(progress.nextLevel(in: .jellyBloom) == 0)
        #expect((0..<5).allSatisfy { progress.isOpen(.jellyBloom, $0) })
    }

    @Test func corruptSaveFallsBackAndLessonPersists() {
        let (_, defaults) = fresh()
        defaults.set(Data("bad save".utf8), forKey: ArcadeProgress.key)
        let progress = ArcadeProgress(defaults: defaults)
        #expect(progress.save.clearedLevels.isEmpty)
        progress.sawJellyLesson()
        #expect(ArcadeProgress(defaults: defaults).save.hasSeenJellyLesson)
    }

    @Test func levelIDsAreUniqueAndOriginalWorldHasNoHazards() {
        let ids = ArcadeWorld.allCases.flatMap { world in world.levels.indices.map { world.levelID($0) } }
        #expect(Set(ids).count == 10)
        #expect(ids.first == "shallow-reef.1")
        #expect(ids.last == "jelly-bloom.5")
        #expect(GameTuning.levels.allSatisfy { $0.jellies == nil })
        #expect(GameTuning.bloomLevels.allSatisfy { $0.jellies != nil })
        #expect(!GameTuning.bloomLevels[0].aiCanEat)
        #expect(GameTuning.bloomLevels[0].spawnGroups.allSatisfy { $0.radii.upperBound < 1 })
    }
}

struct JellyRulesTests {
    private func contact(_ x: Double, _ y: Double, from previous: CGPoint? = nil) -> JellyContact {
        let p = CGPoint(x: x, y: y)
        return JellyRules.contact(at: p, previous: previous ?? p, fishRadius: 16,
                                 domeRadius: 40, tentacleLength: 90)
    }

    @Test func fallingOntoDomeBouncesIncludingFastCrossings() {
        #expect(contact(0, 36, from: CGPoint(x: 0, y: 55)) == .bounce)
        #expect(contact(0, -12, from: CGPoint(x: 0, y: 65)) == .bounce)
        #expect(contact(40, 25, from: CGPoint(x: 40, y: 50)) == .bounce)
    }

    @Test func curtainAndUndersideAreLethal() {
        #expect(contact(0, -40) == .tentacles)
        #expect(contact(0, -5, from: CGPoint(x: 0, y: -20)) == .tentacles)
        #expect(contact(38, -40) == .tentacles)
    }

    @Test func wideAndHighPassesAreSafe() {
        #expect(contact(80, 10) == .none)
        #expect(contact(0, 80) == .none)
        #expect(contact(0, -120) == .none)
    }

    @Test func crossingCurtainBetweenFramesIsStillLethal() {
        #expect(contact(90, -40, from: CGPoint(x: -90, y: -40)) == .tentacles)
        #expect(contact(90, 80, from: CGPoint(x: -90, y: 80)) == .none)
    }
}

@MainActor
struct ArcadeSceneTests {
    private func scene(level: Int = 0) -> (GameScene, SKView) {
        let scene = GameScene(size: CGSize(width: 852, height: 393), world: .jellyBloom, levelIndex: level)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 852, height: 393))
        view.presentScene(scene)
        scene.debugStart()
        return (scene, view)
    }

    @Test func gauntletCannotClearFromHazardsAloneAndReplenishesFood() {
        let (scene, view) = scene(level: 4)
        var clears = 0
        scene.onClear = { _, _ in clears += 1 }
        scene.debugHazardWipeout()
        #expect(clears == 0)
        #expect(scene.debugMealsEaten == 0)
        #expect(scene.debugResultTitles.isEmpty)
        #expect(scene.debugEdibleCount == GameTuning.bloomFoodRefillCount)
        for _ in 0..<7 { scene.debugEatMeal() }
        #expect(scene.debugMealsEaten == 7)
        #expect(clears == 0)
        scene.debugEatMeal()
        scene.debugHazardWipeout()
        #expect(clears == 1)
        #expect(scene.debugMealsEaten == 8)
        scene.debugTapResult(.playAgain)
        #expect(scene.debugMealsEaten == 0)
        withExtendedLifetime(view) {}
    }

    @Test func domeContactActuallyImpulsesThePlayer() {
        let (scene, view) = scene()
        #expect(scene.debugFallOntoDome())
        withExtendedLifetime(view) {}
    }

    @Test func tentaclesEndTheRunAndAlsoRemoveAI() {
        let (scene, view) = scene()
        #expect(scene.debugTouchTentacles(playerVictim: false))
        #expect(scene.debugTouchTentacles(playerVictim: true))
        withExtendedLifetime(view) {}
    }

    @Test func distantWrappedHazardsCannotCausePhantomHits() {
        let (jellyScene, jellyView) = scene()
        #expect(jellyScene.debugPassOppositeJelly())
        let (urchinScene, urchinView) = scene(level: 1)
        #expect(urchinScene.debugPassOppositeUrchin())
        withExtendedLifetime((jellyView, urchinView)) {}
    }

    @Test func laterLevelsHaveLethalUrchinBeds() {
        for index in 1..<5 {
            let (scene, view) = scene(level: index)
            #expect(scene.debugTouchUrchin())
            withExtendedLifetime(view) {}
        }
    }

    @Test func winOffersExplicitChoicesAndOutsideTapDoesNotAdvance() {
        let (scene, view) = scene()
        scene.debugClearLevel()
        #expect(scene.debugResultTitles == ["Next level", "Play again", "Levels"])
        scene.debugTapResult(nil)
        #expect(scene.debugLevelIndex == 0)
        scene.debugTapResult(.nextLevel)
        #expect(scene.debugLevelIndex == 1)
        #expect(scene.debugResultTitles.isEmpty)
        withExtendedLifetime(view) {}
    }

    @Test func finalLevelHasReplayAndLevelsWithoutRestartingCampaign() {
        let (scene, view) = scene(level: 4)
        var exits = 0
        scene.onExit = { exits += 1 }
        scene.debugClearLevel()
        #expect(scene.debugResultTitles == ["Play again", "Levels"])
        scene.debugTapResult(.playAgain)
        #expect(scene.debugLevelIndex == 4)
        scene.debugStart()
        scene.debugClearLevel()
        scene.debugTapResult(.levels)
        #expect(exits == 1)
        withExtendedLifetime(view) {}
    }

    @Test func lossOffersRetryAndLevels() {
        let (scene, view) = scene()
        #expect(scene.debugTouchTentacles(playerVictim: true))
        #expect(scene.debugResultTitles == ["Try again", "Levels"])
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugLevelIndex == 0)
        #expect(scene.debugResultTitles.isEmpty)
        withExtendedLifetime(view) {}
    }

    @Test func clearingCallsProgressOnceEvenAcrossMoreFrames() {
        let (scene, view) = scene()
        var clears: [Int] = []
        scene.onClear = { index, seconds in
            clears.append(index)
            #expect(seconds > 0)
        }
        scene.debugClearLevel()
        scene.debugClearLevel()
        #expect(clears == [0])
        withExtendedLifetime(view) {}
    }
}
