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

    @Test func bounceUsesOnlyTheTimeAfterContact() {
        // At the dome center a radius-16 fish contacts at y=38.8.
        func remaining(from: CGFloat, to: CGFloat, dt: CGFloat = 1.0 / 60) -> CGFloat {
            JellyRules.remainingBounceTime(at: CGPoint(x: 0, y: to), previous: CGPoint(x: 0, y: from),
                                          fishRadius: 16, domeRadius: 40, dt: dt)
        }
        #expect(abs(remaining(from: 43.8, to: 33.8) - 1.0 / 120) < 0.000001)
        #expect(abs(remaining(from: 43.8, to: 38.8)) < 0.000001)
        #expect(abs(remaining(from: 38.8, to: 33.8) - 1.0 / 60) < 0.000001)
        #expect(remaining(from: 43.8, to: 33.8, dt: 0) == 0)
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

    @Test func pursuitBudgetStartsAfterTurningAndPreyDoNotFlee() {
        let (scene, view) = scene(level: 3)
        let timing = scene.debugPredatorTiming()
        #expect(abs(timing.turning - 2.5) < 0.000001)
        #expect(abs(timing.pursuing - 2.0) < 0.000001)
        #expect(scene.debugPreyUsesOrdinarySwimming())
        withExtendedLifetime(view) {}
    }

    @Test func nightBloomSeparatesPredatorsAndKeepsAGrownFishLane() {
        let (scene, view) = scene(level: 3)
        #expect(scene.debugPredatorStartGaps.count == 10) // All five predators still spawn.
        #expect(scene.debugPredatorStartGaps.allSatisfy { $0 >= 0.45 })
        for radius: CGFloat in [16, 40, 80] {
            #expect(scene.debugFloorLane(radius: radius) >= GameRules.bloomFloorLaneClearance(fishRadius: radius) - 0.000001)
        }
        withExtendedLifetime(view) {}
    }

    @Test func gauntletKeepsAllPredatorsWithSpacedStartsAndAGrownFishLane() {
        let (scene, view) = scene(level: 4)
        #expect(GameTuning.bloomLevels[4].jellies?.count == 7)
        #expect(scene.debugPredatorStartGaps.count == 15) // All six predators still spawn.
        #expect(scene.debugPredatorStartGaps.allSatisfy { $0 >= 0.4 })
        for radius: CGFloat in [16, 40, 80] {
            #expect(scene.debugFloorLane(radius: radius) >= GameRules.bloomFloorLaneClearance(fishRadius: radius) - 0.000001)
        }
        withExtendedLifetime(view) {}
    }

    @Test func nearbyLargerFishEngageAndOrdinarySwimmersAvoidUrchins() {
        let (scene, view) = scene(level: 4)
        #expect(scene.debugEngagesNearbyPlayer())
        #expect(scene.debugApproachUrchin(chasing: false))
        let (chaser, chaserView) = self.scene(level: 4)
        #expect(!chaser.debugApproachUrchin(chasing: true))
        withExtendedLifetime((view, chaserView)) {}
    }

    @Test func campaignWinsWithoutMealQuotaOrReplenishment() {
        let (scene, view) = scene(level: 4)
        var clears = 0
        scene.onClear = { _, _ in clears += 1 }
        #expect(!scene.debugMealHUDVisible)
        scene.debugHazardWipeout()
        #expect(clears == 1)
        #expect(scene.debugMealsEaten == 0)
        #expect(scene.debugEdibleCount == 0)
        #expect(scene.debugResultTitles == ["Play again", "Levels"])
        withExtendedLifetime(view) {}
    }

    @Test func ordinarySwimmersAvoidCurtainsButChasesCanBeBaited() {
        let (ordinary, ordinaryView) = scene(level: 3)
        #expect(ordinary.debugApproachJelly(chasing: false))
        let (chaser, chaserView) = scene(level: 3)
        #expect(!chaser.debugApproachJelly(chasing: true))
        withExtendedLifetime((ordinaryView, chaserView)) {}
    }

    @Test func domeContactActuallyImpulsesThePlayer() {
        let (scene, view) = scene()
        #expect(scene.debugFallOntoDome())
        #expect(scene.debugBounceRiseInContactFrame > 0)
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
