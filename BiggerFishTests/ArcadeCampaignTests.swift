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
        for world in ArcadeWorld.campaign {
            #expect(progress.mapFocus(in: world) == 0)
            #expect(progress.isOpen(world, 0))
            #expect(!progress.isOpen(world, 1))
            #expect(!progress.isOpen(world, -1))
            #expect(!progress.isOpen(world, world.levels.count))
            // Ten levels, then five in the Deep End.
            #expect(world.levels.count == 15)
        }
    }

    @Test func worldsOpenInOrderAndPlayersKeepWorldsTheyStarted() {
        let (progress, _) = fresh()
        #expect(progress.isWorldOpen(.shallowReef) && !progress.isWorldOpen(.jellyBloom))
        for index in 0..<9 { progress.clear(.shallowReef, index, seconds: 20) }
        #expect(!progress.isWorldOpen(.jellyBloom))
        progress.clear(.shallowReef, 9, seconds: 20)
        #expect(progress.isWorldOpen(.jellyBloom))
        // The Deep End opens with the tenth level and counts apart from the main run.
        #expect(progress.isOpen(.shallowReef, ArcadeWorld.mainLevelCount) && !progress.isOpen(.shallowReef, 11))
        progress.clear(.shallowReef, 10, seconds: 40)
        #expect(progress.clearedCounts(in: .shallowReef) == (main: 10, deepEnd: 1))

        // Someone who played Jelly Bloom before worlds were locked keeps it open.
        let (earlier, _) = fresh()
        earlier.clear(.jellyBloom, 0, seconds: 30)
        #expect(earlier.isWorldOpen(.jellyBloom))
        #expect(ArcadeWorld.jellyBloom.previousWorld == .shallowReef && ArcadeWorld.shallowReef.nextWorld == .jellyBloom)
        #expect(ArcadeWorld.campaign.allSatisfy { $0.deepEndCount == $0.levelCount - ArcadeWorld.mainLevelCount })
    }

    /// A playtester noticed Jelly Bloom's level 1 and level 2 cards said different things: each world says
    /// the same thing everywhere, and Jelly Bloom calls its jellyfish's parts tops and tentacles.
    @Test func eachWorldDescribesItselfOneWay() {
        for world in ArcadeWorld.campaign {
            #expect(world.levelCard.count == 3 && world.levelCard.last == "Be the last fish swimming.")
        }
        let jelly = ([ArcadeWorld.jellyBloom.subtitle] + ArcadeWorld.jellyBloom.levelCard).joined(separator: " ").lowercased()
        #expect(jelly.contains("tops") && jelly.contains("tentacles"))
        for other in ["bell", "dome", "bottom", "sting"] { #expect(!jelly.contains(other), "Jelly Bloom says \(other)") }
        #expect(ArcadeWorld.kelpForest.levelCard.joined().lowercased().contains("kelp"))
    }

    /// Progress must survive every update. These are the shapes a stored save can take.
    @Test func savesFromEveryVersionAndEvenBrokenOnesKeepProgress() throws {
        func load(_ json: String) -> (ArcadeProgress, UserDefaults) {
            let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
            defaults.set(Data(json.utf8), forKey: ArcadeProgress.key)
            return (ArcadeProgress(defaults: defaults), defaults)
        }
        // Exactly what 0.1 wrote.
        let (first, _) = load(#"{"clearedLevels":["shallow-reef.1","shallow-reef.2"],"bestTimes":{"shallow-reef.1":21.5},"hasSeenJellyLesson":false}"#)
        #expect(first.isCleared(.shallowReef, 1) && first.save.bestTimes["shallow-reef.1"] == 21.5)
        // Missing fields, and fields from a later version, are fine.
        let (sparse, _) = load(#"{"clearedLevels":["jelly-bloom.3"]}"#)
        #expect(sparse.isCleared(.jellyBloom, 2) && sparse.save.bestTimes.isEmpty)
        let (later, _) = load(#"{"clearedLevels":["kelp-forest.1"],"bestTimes":{},"hasSeenJellyLesson":true,"somethingNew":[1,2]}"#)
        #expect(later.isCleared(.kelpForest, 0))
        // A field of the wrong type loses only that field.
        let (odd, _) = load(#"{"clearedLevels":["shallow-reef.5"],"bestTimes":"oops"}"#)
        #expect(odd.isCleared(.shallowReef, 4) && odd.save.bestTimes.isEmpty)
        // A save that can't be read at all is kept, and clearing a level afterwards doesn't destroy it.
        let (broken, defaults) = load("not a save")
        #expect(broken.save.clearedLevels.isEmpty)
        broken.clear(.shallowReef, 0, seconds: 20)
        #expect(defaults.data(forKey: ArcadeProgress.unreadableKey) == Data("not a save".utf8))
    }

    @Test func playersWhoBeatATenthLevelEarlierSeeItsUnlockScreenOnce() throws {
        // A save from before unlock screens were remembered: both worlds' tenth levels beaten.
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        let old = #"{"clearedLevels":["shallow-reef.10","jelly-bloom.1","jelly-bloom.10"],"bestTimes":{},"hasSeenJellyLesson":true}"#
        defaults.set(Data(old.utf8), forKey: ArcadeProgress.key)
        let progress = ArcadeProgress(defaults: defaults)
        #expect(progress.isCleared(.jellyBloom, 9) && progress.save.hasSeenJellyLesson)
        // The furthest one announces the newest things; once shown, neither it nor earlier ones come back.
        #expect(progress.unseenUnlock == .jellyBloom)
        progress.sawUnlock(.jellyBloom)
        #expect(ArcadeProgress(defaults: defaults).unseenUnlock == nil)

        let (fresh, _) = fresh()
        #expect(fresh.unseenUnlock == nil)
        fresh.clear(.shallowReef, 9, seconds: 30)
        #expect(fresh.unseenUnlock == .shallowReef)
    }

    /// Midnight Zone joined after 0.2, whose Kelp Forest "conquered" screen said more worlds were coming. Players
    /// who'd beaten Kelp Forest see that screen once more, now announcing Midnight Zone; nobody else does.
    @Test func playersWhoBeatKelpForestBeforeMidnightZoneAreToldOnce() throws {
        func load(_ json: String) -> (ArcadeProgress, UserDefaults) {
            let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
            defaults.set(Data(json.utf8), forKey: ArcadeProgress.key)
            return (ArcadeProgress(defaults: defaults), defaults)
        }
        #expect(ArcadeWorld.kelpForest.nextWorld == .midnightZone && ArcadeWorld.lateArrivals == [.midnightZone])
        // Exactly what 0.2 wrote after beating Kelp Forest and seeing its screen.
        let saved02 = #"{"clearedLevels":["shallow-reef.10","jelly-bloom.10","kelp-forest.10"],"bestTimes":{"kelp-forest.10":41.2},"hasSeenJellyLesson":true,"seenUnlocks":["shallow-reef","jelly-bloom","kelp-forest"]}"#
        let (beaten, defaults) = load(saved02)
        #expect(beaten.save.announcedWorlds == nil && beaten.isWorldOpen(.midnightZone))
        #expect(beaten.unseenUnlock == .kelpForest)
        beaten.sawUnlock(.kelpForest)
        #expect(ArcadeProgress(defaults: defaults).unseenUnlock == nil)
        #expect(ArcadeProgress(defaults: defaults).save.announcedWorlds?.contains("midnight-zone") == true)
        // Already played Midnight Zone: nothing to announce.
        let (played, _) = load(#"{"clearedLevels":["kelp-forest.10","midnight-zone.1"],"seenUnlocks":["shallow-reef","jelly-bloom","kelp-forest"]}"#)
        #expect(played.unseenUnlock == nil)
        // Only up to Jelly Bloom's screen, which already announced Kelp Forest: nothing new either.
        let (earlier, _) = load(#"{"clearedLevels":["shallow-reef.10","jelly-bloom.10"],"seenUnlocks":["shallow-reef","jelly-bloom"]}"#)
        #expect(earlier.unseenUnlock == nil)
        // Beating Kelp Forest from now on shows the screen with Midnight Zone on it once, as usual.
        let (fresh, _) = fresh()
        fresh.clear(.kelpForest, 9, seconds: 40)
        #expect(fresh.unseenUnlock == .kelpForest)
        fresh.sawUnlock(.kelpForest)
        #expect(fresh.unseenUnlock == nil)
    }

    /// Everything that ships plays saved plans, never plans on the device (AGENTS.md: freeze before publishing).
    @Test func everyCampaignLevelIsFrozen() {
        let frozen: [ArcadeWorld: (specs: [MeetingSpec], frozen: Set<String>)] = [
            .shallowReef: (GameTuning.reefLabSpecs, GameTuning.reefLabFrozen),
            .jellyBloom: (GameTuning.jellyLabSpecs, GameTuning.jellyLabFrozen),
            .kelpForest: (GameTuning.kelpSpecs, GameTuning.kelpFrozen),
            .midnightZone: (GameTuning.midnightSpecs, GameTuning.midnightFrozen),
        ]
        #expect(Set(frozen.keys) == Set(ArcadeWorld.campaign), "a campaign world has no frozen set here")
        for (world, levels) in frozen {
            #expect(Set(levels.specs.map(\.name)).isSubset(of: levels.frozen), "\(world.title) has levels that aren't frozen")
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
        #expect(restored.mapFocus(in: .jellyBloom) == 1)
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
        for world in ArcadeWorld.campaign {
            for index in world.levels.indices { progress.clear(world, index, seconds: 30) }
            #expect(progress.nextLevel(in: world) == 0)
            #expect(progress.mapFocus(in: world) == world.levels.count - 1)
            // Coming back from a level, the marker sits on that level instead, even a replayed early one.
            #expect(progress.mapFocus(in: world, returningFrom: 2) == 2)
            #expect(progress.mapFocus(in: world, returningFrom: 99) == world.levels.count - 1)
            #expect(world.levels.indices.allSatisfy { progress.isOpen(world, $0) })
        }
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
        let ids = ArcadeWorld.campaign.flatMap { world in world.levels.indices.map { world.levelID($0) } }
        #expect(Set(ids).count == 60)
        #expect(ids.first == "shallow-reef.1")
        #expect(ids.contains("shallow-reef.15") && ids.contains("jelly-bloom.15") && ids.contains("kelp-forest.15")
            && ids.last == "midnight-zone.15")
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
        let scene = GameScene(world: .jellyBloom, levelIndex: level, seeded: true)
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
        #expect(scene.debugResultTitles == ["Back to world", "Play again"])
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
        for world in ArcadeWorld.campaign {
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
        #expect(scene.debugResultTitles == ["Back to world", "Play again"])
        scene.debugTapResult(.playAgain)
        #expect(scene.debugLevelIndex == 4)
        scene.debugStart()
        scene.debugClearLevel()
        scene.debugTapResult(.world)
        #expect(exits == 1)
        withExtendedLifetime(view) {}
    }

    @Test func lossOffersRetryAndLevels() {
        let (scene, view) = scene()
        #expect(scene.debugTouchTentacles(playerVictim: true))
        // The result waits for the sting animation.
        #expect(scene.debugResultTitles.isEmpty)
        scene.debugAdvance(seconds: GameTuning.stingResultDelay + 0.05)
        #expect(scene.debugResultTitles == ["Retry", "Levels"])
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
