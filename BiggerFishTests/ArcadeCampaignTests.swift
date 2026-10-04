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
            #expect(!progress.isOpen(world, world.levels.count))
            #expect(world.levels.count == (world == .jellyBloom ? 10 : 5))
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
        for index in ArcadeWorld.jellyBloom.levels.indices { progress.clear(.jellyBloom, index, seconds: 30) }
        #expect(progress.nextLevel(in: .jellyBloom) == 0)
        #expect(ArcadeWorld.jellyBloom.levels.indices.allSatisfy { progress.isOpen(.jellyBloom, $0) })
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
        #expect(Set(ids).count == 15)
        #expect(ids.first == "shallow-reef.1")
        #expect(ids.last == "jelly-bloom.10")
        #expect(GameTuning.levels.allSatisfy { $0.jellies == nil })
        #expect(GameTuning.bloomLevels.allSatisfy { $0.jellies != nil })
        #expect(GameTuning.bloomLevels.allSatisfy { $0.aiCanEat })
        #expect(GameTuning.bloomLevels.allSatisfy { $0.encounterDifficulty != nil })
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
        let scene = GameScene(world: .jellyBloom, levelIndex: level)
        scene.debugUseReferenceLevel()
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 852, height: 393))
        view.presentScene(scene)
        scene.debugStart()
        return (scene, view)
    }

    @Test func onlyLevelTwoHasTheFarShoulderMealExperiment() {
        #expect(GameTuning.bloomReferenceLevels.enumerated().filter { $0.element.sidePocketExperiment }.map(\.offset) == [1])
        let (scene, view) = scene(level: 1)
        let pocket = scene.debugSidePocketPlacement
        #expect(!pocket.food.isEmpty)
        #expect(pocket.predators.count == 1)
        #expect(pocket.safe)
        #expect(pocket.food.allSatisfy { $0.x > 44 && $0.y < 10 })
        #expect(pocket.predators.allSatisfy { $0.x > 150 && abs($0.y + 16) <= 24 })
        withExtendedLifetime(view) {}
    }

    @Test func foodLeavesItsOpeningPocketToJoinTheFoodChain() {
        for index in 1..<5 {
            let (scene, view) = scene(level: index)
            #expect(scene.debugFoodLeavesPocket())
            withExtendedLifetime(view) {}
        }
    }

    @Test func aiMealsCanTurnEdibleFishIntoThreatsInEveryBloomLevel() {
        for index in 0..<5 {
            let (scene, view) = scene(level: index)
            let result = scene.debugAICompetition()
            #expect(result.respectedGrace)
            #expect(result.becameThreat)
            withExtendedLifetime(view) {}
        }
    }

    @Test func bounceRoutesKeepFoodPocketsLargerFishAndGrownFishPassages() {
        for index in 1..<5 {
            let (scene, view) = scene(level: index)
            let level = GameTuning.bloomReferenceLevels[index]
            #expect(scene.debugFoodPocketCount >= 8)
            #expect(scene.debugFishCount == level.spawnGroups.reduce(1) { $0 + $1.count })
            #expect(scene.debugAllPredatorsInitiallyLarger)
            #expect(scene.debugUrchinCount == 0)
            for radius: CGFloat in [16, 40, 80] {
                #expect(scene.debugFloorLane(radius: radius) >= GameRules.bloomFloorLaneClearance(fishRadius: radius) - 0.000001)
            }
            withExtendedLifetime(view) {}
        }
    }

    @Test func largerFishDoNotSteerTowardThePlayer() {
        let (first, firstView) = scene(level: 3)
        let (second, secondView) = scene(level: 3)
        #expect(first.debugPassivePredatorVelocity(playerOffset: -60) == second.debugPassivePredatorVelocity(playerOffset: 60))
        withExtendedLifetime((firstView, secondView)) {}
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

    @Test func swimmersStillAvoidTentacleCurtains() {
        let (scene, view) = scene(level: 3)
        #expect(scene.debugApproachJelly())
        withExtendedLifetime(view) {}
    }

    @Test func domeContactActuallyImpulsesThePlayer() {
        let (scene, view) = scene()
        #expect(scene.debugFallOntoDome())
        #expect(scene.debugBounceRiseInContactFrame > 0)
        withExtendedLifetime(view) {}
    }

    @Test func tentaclesEndTheRunButNeverRemoveAI() {
        let (scene, view) = scene()
        #expect(scene.debugTouchTentacles(playerVictim: false))
        #expect(scene.debugTouchTentacles(playerVictim: true))
        withExtendedLifetime(view) {}
    }

    @Test func distantWrappedHazardsCannotCausePhantomHits() {
        let (jellyScene, jellyView) = scene()
        #expect(jellyScene.debugPassOppositeJelly())
        withExtendedLifetime(jellyView) {}
    }

    @Test func allBloomLevelsHaveNoUrchinsAndUseNumberedTitles() {
        for world in ArcadeWorld.allCases {
            #expect(world.levelTitles == world.levels.indices.map { "Level \($0 + 1)" })
        }
        #expect(GameTuning.bloomLevels.allSatisfy { $0.jellies?.urchinBeds == 0 })
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

struct JellyPlacementTests {
    @Test func layoutsAreRepeatableUnevenAndKeepSafeSpacing() {
        for width: CGFloat in [667, 874] {
            for index in 1..<5 {
                let layout = GameTuning.bloomReferenceLevels[index].jellies!
                let seed = GameTuning.spawnSeed + UInt64(index + 1_000)
                let points = JellyPlacement.origins(layout: layout, screenWidth: width,
                    waterBottom: 10, waterTop: 390, seed: seed)
                #expect(points == JellyPlacement.origins(layout: layout, screenWidth: width,
                    waterBottom: 10, waterTop: 390, seed: seed))
                #expect(points.count == layout.count)
                #expect(points.first!.x >= width * 0.8)
                #expect(points.last!.x <= width * 3.6 + 0.000001)
                let gaps = zip(points, points.dropFirst()).map { $1.x - $0.x }
                #expect(gaps.min()! >= layout.radius * 2 + layout.sway * 2
                        + GameTuning.bloomJellySpacingPadding - 0.000001)
                #expect(gaps.max()! - gaps.min()! > 40)
                #expect(Set(points.map(\.y)).count > 1)
                #expect(points.allSatisfy { $0.y - layout.tentacleLength - 10 >=
                    GameRules.bloomFloorLaneClearance(fishRadius: GameTuning.baseRadius) - 0.000001 })
            }
        }
    }
}
