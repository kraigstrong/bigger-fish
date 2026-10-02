import Foundation
import Testing
@testable import BiggerFish

struct ArcadeTuningTests {
    @Test func editsAreBoundedBeforeCreatingPhysicsRanges() {
        var tuning = ArcadeTuning(level: GameTuning.bloomLevels[1])
        tuning.groups = [.init(count: 999, minimum: 2, maximum: 0.5)]
        tuning.aiMinimum = 150
        tuning.aiMaximum = 30
        tuning.absorption = .nan
        tuning.jellyCount = 0
        tuning.seedOffset = -1
        let value = tuning.sanitized
        #expect(value.groups[0].count == 8)
        #expect(value.groups[0].maximum == 2)
        #expect(value.aiMaximum == 150)
        #expect(value.absorption == 0.78)
        #expect(value.seedOffset == 0)
        let level = value.applying(to: GameTuning.bloomLevels[1])
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
        var tuning = ArcadeTuning(level: GameTuning.bloomLevels[1])
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
        var tuning = ArcadeTuning(level: GameTuning.bloomLevels[1])
        tuning.jellyCount = 1
        let level = tuning.applying(to: GameTuning.bloomLevels[1])
        #expect(level.jellies?.count == 1)
        #expect(level.jellies?.maintainsFloorLane == true)
        #expect(!level.sidePocketExperiment)
        #expect(level.bounceFoodPockets)
    }
}
