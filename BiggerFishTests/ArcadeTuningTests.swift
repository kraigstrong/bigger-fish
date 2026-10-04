import Foundation
import Testing
@testable import BiggerFish

struct ArcadeTuningTests {
    @Test func movedSetupControlsToggledDifficultyAndPreviewSeed() {
        for index in [2, 5, 6] {
            let level = GameTuning.bloomLevels[index]
            var draft = ArcadeTuning(level: level)
            draft.setEncounterDifficultyEnabled(false, for: level)
            #expect(draft.difficulty == nil)
            draft.setEncounterDifficultyEnabled(true, for: level)
            #expect(draft.difficulty == level.encounterDifficulty?.bounded)
            for offset in [draft.seedOffset, 987] {
                draft.seedOffset = offset
                let preview = draft.encounterWaveBudgets(for: level, index: index, bloom: true)
                let gameplay = GameTuning.freeEncounterWaveBudgets(
                    seed: level.spawnSeed(index: index, bloom: true, offset: UInt64(offset)),
                    difficulty: level.encounterDifficulty!.bounded, preserveLevelTwo: false)
                #expect(preview.map(\.count) == gameplay.map(\.count))
                #expect(preview.map(\.edible) == gameplay.map(\.edible))
            }
        }
    }

    @Test func reorderedSetupsKeepTheirSeedsAndTuning() {
        let easy = GameTuning.bloomLevels[2]
        let fair = GameTuning.bloomLevels[5]
        let hard = GameTuning.bloomLevels[6]
        #expect(easy.spawnSeed(index: 2, bloom: true) == 20261033)
        #expect(fair.spawnSeed(index: 5, bloom: true) == 20261477)
        #expect(hard.spawnSeed(index: 6, bloom: true) == 20261033)
        #expect(easy.encounterDifficulty?.bounded == 5.0 / 9)
        #expect(fair.encounterDifficulty?.bounded == 6.0 / 9)
        #expect(hard.encounterDifficulty?.bounded == 2.0 / 9)
        for index in GameTuning.bloomLevels.indices {
            let source = GameTuning.bloomCampaignOrder[index]
            let original = GameTuning.bloomLevelSetups[source]
            let moved = GameTuning.bloomLevels[index]
            #expect(ArcadeTuning(level: moved) == ArcadeTuning(level: original))
            #expect(moved.spawnSeed(index: index, bloom: true) == original.spawnSeed(index: source, bloom: true))
            let applied = ArcadeTuning(level: moved).applying(to: moved)
            #expect(applied.spawnSeed(index: index, bloom: true) == moved.spawnSeed(index: index, bloom: true))
        }
    }

    @Test func existingOverridesMoveOnceWithTheirLevelsIncludingRerolledSeeds() throws {
        let name = "biggerFish.tuning.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let third = ArcadeTuning(level: GameTuning.bloomLevelSetups[2]).sanitized
        let sixth = ArcadeTuning(level: GameTuning.bloomLevelSetups[5]).sanitized
        var seventh = ArcadeTuning(level: GameTuning.bloomLevelSetups[6]).sanitized
        seventh.seedOffset = 444
        let fourth = ArcadeTuning(level: GameTuning.bloomReferenceLevels[3])
        let old = ["jelly-bloom.3": third, "jelly-bloom.6": sixth,
                   "jelly-bloom.7": seventh, "jelly-bloom.4": fourth]
        defaults.set(try JSONEncoder().encode(old), forKey: "biggerFish.debug.tuning.v1")
        let migrated = ArcadeTuningStore(defaults: defaults)
        #expect(migrated.override(.jellyBloom, 2) == sixth)
        #expect(migrated.override(.jellyBloom, 5) == seventh)
        #expect(migrated.override(.jellyBloom, 6) == third)
        #expect(migrated.override(.jellyBloom, 3) == fourth)
        #expect(seventh.applying(to: GameTuning.bloomLevels[5]).spawnSeed(index: 5, bloom: true) == 20261477)
        var edited = sixth
        edited.seedOffset = 123
        migrated.save(edited, world: .jellyBloom, index: 2)
        let reloaded = ArcadeTuningStore(defaults: defaults)
        #expect(reloaded.override(.jellyBloom, 2) == edited)
        #expect(reloaded.override(.jellyBloom, 5) == seventh)
        #expect(reloaded.override(.jellyBloom, 6) == third)
    }

    @Test func oldSavedTuningStillDecodesAndNewDifficultyRegeneratesTheBudget() throws {
        let original = ArcadeTuning(level: GameTuning.bloomReferenceLevels[3])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "difficulty")
        let restored = try JSONDecoder().decode(ArcadeTuning.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored == original)
        var draft = ArcadeTuning(level: GameTuning.bloomLevels[0])
        draft.difficulty = 1
        draft.jellyCount = 0
        let level = draft.applying(to: GameTuning.bloomLevels[0])
        #expect(level.encounterDifficulty?.minimumCatches == 11)
        #expect(level.jellies?.count == 4)
        #expect(GameTuning.freeEncounterExpectedCatchFraction(level.encounterDifficulty!.bounded) > GameTuning.freeEncounterExpectedCatchFraction(0))
        #expect(level.freeEncounterMovement)
        #expect(try JSONDecoder().decode(ArcadeTuning.self, from: JSONEncoder().encode(draft)) == draft)
    }

    @Test func editsAreBoundedBeforeCreatingPhysicsRanges() {
        var tuning = ArcadeTuning(level: GameTuning.bloomReferenceLevels[1])
        tuning.groups = [.init(count: 999, minimum: 2, maximum: 0.5)]
        tuning.aiMinimum = 150
        tuning.aiMaximum = 30
        tuning.absorption = .nan
        tuning.jellyCount = 0
        tuning.seedOffset = -1
        let value = tuning.sanitized
        #expect(value.groups[0].count == 12)
        #expect(value.groups[0].maximum == 2)
        #expect(value.aiMaximum == 150)
        #expect(value.absorption == 0.78)
        #expect(value.seedOffset == 0)
        let level = value.applying(to: GameTuning.bloomReferenceLevels[1])
        #expect(level.jellies == nil)
        #expect(!level.sidePocketExperiment)
        #expect(!level.bounceFoodPockets)
        #expect(level.aiCanEat)
    }

    @Test func overridesAndPresetsPersistWithoutCrossingLevelOrCampaignKeys() {
        let name = "biggerFish.tuning.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ArcadeTuningStore(defaults: defaults)
        var tuning = ArcadeTuning(level: GameTuning.bloomReferenceLevels[1])
        tuning.aiMaximum = 100
        tuning.releaseSeconds = 8
        store.save(tuning, world: .jellyBloom, index: 1)
        store.savePreset(name: "Experiment", tuning: tuning)
        let reloaded = ArcadeTuningStore(defaults: defaults)
        #expect(reloaded.override(.jellyBloom, 1) == tuning)
        #expect(reloaded.override(.jellyBloom, 2) == nil)
        #expect(reloaded.override(.shallowReef, 1) == nil)
        #expect(reloaded.presets.first?.tuning == tuning)
        #expect(defaults.data(forKey: ArcadeProgress.key) == nil)
        reloaded.clear(world: .jellyBloom, index: 1)
        #expect(reloaded.override(.jellyBloom, 1) == nil)
        #expect(reloaded.presets.count == 1)
    }

    @Test func tuningCanReduceJelliesWithoutAnInvalidSidePocket() {
        var tuning = ArcadeTuning(level: GameTuning.bloomReferenceLevels[1])
        tuning.jellyCount = 1
        let level = tuning.applying(to: GameTuning.bloomReferenceLevels[1])
        #expect(level.jellies?.count == 1)
        #expect(level.jellies?.maintainsFloorLane == true)
        #expect(!level.sidePocketExperiment)
        #expect(level.bounceFoodPockets)
    }
}
