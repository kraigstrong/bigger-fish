import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

struct ShallowCampaignTests {
    @MainActor @Test func shallowCampaignAdvancesToTenAndReplaysItsFinalLevel() {
        for index in [0, 8, 9] {
            let scene = GameScene(world: .shallowReef, levelIndex: index)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            scene.debugStart()
            var cleared: [Int] = []
            var exits = 0
            scene.onClear = { level, _ in cleared.append(level) }
            scene.onExit = { exits += 1 }
            scene.debugClearLevel()
            #expect(cleared == [index])
            if index == 9 {
                #expect(scene.debugResultTitles == ["Play again", "Levels"])
                scene.debugTapResult(.playAgain)
                #expect(scene.debugLevelIndex == 9)
                #expect(scene.debugFishCount == 21)
                scene.debugStart()
                scene.debugClearLevel()
                scene.debugTapResult(.levels)
                #expect(exits == 1)
            } else {
                #expect(scene.debugResultTitles == ["Next level", "Play again", "Levels"])
                scene.debugTapResult(.nextLevel)
                #expect(scene.debugLevelIndex == index + 1)
                #expect(scene.debugFishCount == 21)
            }
            withExtendedLifetime(view) {}
        }
    }

    @Test func tenFishOnlyLevelsMatchBloomGrowthAndIncreaseCatchTargets() {
        #expect(GameTuning.levels.count == 10)
        #expect(GameTuning.shallowReferenceLevels.count == 5)
        for (index, level) in GameTuning.shallowLevelSetups.enumerated() {
            #expect(level.jellies == nil)
            #expect(level.freeEncounterMovement && level.aiCanEat)
            #expect(abs(level.effectiveAbsorptionEfficiency - 0.495) < 1e-10)
            #expect(level.spawnGroups.reduce(0) { $0 + $1.count } == 20)
            let fraction = GameTuning.freeEncounterExpectedCatchFraction(level.encounterDifficulty!.bounded, shallow: true)
            #expect(abs(fraction - (0.45 + CGFloat(index) * 0.05)) < 1e-10)
            if index > 0 {
                let previous = GameTuning.shallowLevelSetups[index - 1]
                #expect(level.aiSpeedRange.lowerBound > previous.aiSpeedRange.lowerBound)
                #expect(level.aiSpeedRange.upperBound > previous.aiSpeedRange.upperBound)
                #expect(level.screenCrossSeconds < previous.screenCrossSeconds)
            }
        }
    }

    @Test func movingThirdLevelPreservesItsSetupAndOverrides() throws {
        #expect(GameTuning.shallowCampaignOrder == [0, 1, 3, 4, 5, 6, 7, 2, 8, 9])
        for (destination, source) in GameTuning.shallowCampaignOrder.enumerated() {
            let moved = GameTuning.levels[destination]
            let original = GameTuning.shallowLevelSetups[source]
            #expect(moved.spawnSeed(index: destination, bloom: false) == original.spawnSeed(index: source, bloom: false))
            #expect(ArcadeTuning(level: moved) == ArcadeTuning(level: original))
        }
        #expect(GameTuning.levels[7].spawnSeed(index: 7, bloom: false) == 20260942)
        let name = "biggerFish.shallow.reorder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "biggerFish.debug.tuning.shallow-ten-level.v1")
        var draft = ArcadeTuning(level: GameTuning.shallowLevelSetups[2])
        draft.seedOffset = 777
        defaults.set(try JSONEncoder().encode(["shallow-reef.3": draft]), forKey: "biggerFish.debug.tuning.v1")
        let store = ArcadeTuningStore(defaults: defaults)
        #expect(store.override(.shallowReef, 7) == draft.sanitized)
        #expect(store.override(.shallowReef, 2) == nil)
        #expect(ArcadeTuningStore(defaults: defaults).override(.shallowReef, 7) == draft.sanitized)
    }

    @MainActor @Test func originalReferenceUsesTheSelectedOriginalSeedAfterReordering() {
        for index in 0..<5 {
            let reference = GameTuning.shallowReferenceLevels[index]
            let scene = GameScene(world: .shallowReef, levelIndex: index)
            _ = scene.debugSimulate(candidate: "original reference", tuning: ArcadeTuning(level: reference),
                policy: .collector, seed: 0, limit: 0)
            #expect(scene.debugConfiguredSpawnSeed == reference.spawnSeed(index: index, bloom: false))
        }
    }

    @MainActor @Test func seededStartsHaveAllFishAndAnOptimisticGrowthPath() {
        for (index, level) in GameTuning.levels.enumerated() {
            for variation in [0, 7, 33, 987] {
                let scene = GameScene(world: .shallowReef, levelIndex: index)
                let result = scene.debugSimulate(candidate: "shallow spawn audit", tuning: ArcadeTuning(level: level),
                    policy: .collector, seed: variation, limit: 0)
                #expect(result.spawned == 20, "Level \(index + 1), variation \(variation)")
                #expect(result.initialGrowthPath, "Level \(index + 1), variation \(variation)")
            }
            let scene = GameScene(world: .shallowReef, levelIndex: index)
            #expect(scene.debugEncounterSpawnSafety(), "Level \(index + 1)")
        }
    }

    @MainActor @Test func shallowEncountersProtectFoodThenResumeAIEating() {
        for index in [0, 4, 9] {
            let scene = GameScene(world: .shallowReef, levelIndex: index)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            scene.debugStart()
            #expect(scene.debugEncounterProtectionLifecycle())
            withExtendedLifetime(view) {}
        }
    }

    @Test func tunerKeepsFishOnlyEncounterModeAndPreviewsTheActualBudget() {
        for (index, level) in GameTuning.levels.enumerated() {
            let draft = ArcadeTuning(level: level)
            let applied = draft.applying(to: level)
            #expect(applied.freeEncounterMovement)
            #expect(applied.encounterDifficulty?.bounded == level.encounterDifficulty?.bounded)
            #expect(applied.jellies == nil)
            #expect(applied.spawnGroups.reduce(0) { $0 + $1.count } == 20)
            let preview = draft.encounterWaveBudgets(for: level, index: index, bloom: false)
            let actual = GameTuning.freeEncounterWaveBudgets(seed: level.spawnSeed(index: index, bloom: false),
                difficulty: level.encounterDifficulty!.bounded, preserveLevelTwo: false, shallow: true)
            #expect(preview.map(\.edible) == actual.map(\.edible))
            #expect(preview.map(\.count) == actual.map(\.count))
        }
    }

    @Test func originalOverridesAreBackedUpWithoutMaskingNewCampaignSettings() throws {
        let name = "biggerFish.shallow.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let original = ArcadeTuning(level: GameTuning.shallowReferenceLevels[3])
        defaults.set(try JSONEncoder().encode(["shallow-reef.4": original]), forKey: "biggerFish.debug.tuning.v1")
        let store = ArcadeTuningStore(defaults: defaults)
        #expect(store.override(.shallowReef, 3) == nil)
        let backup = try #require(defaults.data(forKey: "biggerFish.debug.tuning.shallow-original-backup.v1"))
        #expect(try JSONDecoder().decode([String: ArcadeTuning].self, from: backup)["shallow-reef.4"] == original)
        let new = ArcadeTuning(level: GameTuning.levels[3]).sanitized
        store.save(new, world: .shallowReef, index: 3)
        #expect(ArcadeTuningStore(defaults: defaults).override(.shallowReef, 3) == new)
    }
}
