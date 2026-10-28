import SpriteKit
import Testing
@testable import BiggerFish

/// An Adventure level counts its fish down at the top once 10 are left, "Last fish!" for the final one (Kraig,
/// 2026-10-27), so the end of a level is in sight.
@MainActor
struct FishLeftTests {
    private func level(_ world: ArcadeWorld, _ index: Int = 0) -> (GameScene, SKView) {
        let scene = GameScene(world: world, levelIndex: index, showsJellyLesson: false)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        return (scene, view)
    }

    /// Shallow Reef 1's 12 fish: nothing at first, then 10 down to "Last fish!", hidden while paused and gone at the win.
    @Test func aLevelCountsDownItsLastTenFish() {
        let (scene, view) = level(.shallowReef)
        #expect(scene.debugFishLeft.count == 12 && scene.debugFishLeft.shown == nil)
        scene.debugRemoveFish(1)
        #expect(scene.debugFishLeft.count == 11 && scene.debugFishLeft.shown == nil)
        scene.debugRemoveFish(1)
        #expect(scene.debugFishLeft.shown == "10 fish left")
        scene.debugRemoveFish(8)
        #expect(scene.debugFishLeft.shown == "2 fish left")
        scene.debugRemoveFish(1)
        #expect(scene.debugFishLeft.shown == "Last fish!")
        scene.debugPauseForTuning()
        #expect(scene.debugFishLeft.shown == nil)
        scene.debugResume()
        #expect(scene.debugFishLeft.shown == "Last fish!")
        var cleared = 0
        scene.onClear = { _, _ in cleared += 1 }
        scene.debugRemoveFish(1)
        #expect(cleared == 1 && scene.debugFishLeft.count == 0 && scene.debugFishLeft.shown == nil)
        withExtendedLifetime(view) {}
    }

    /// Fish still to swim in count from the start, so the number only ever goes down: Kelp Forest 1 starts with 2 of its
    /// 12 fish in the water.
    @Test func fishStillToSwimInCount() throws {
        let (scene, view) = level(.kelpForest)
        let plan = try #require(scene.debugMeetingPlan)
        #expect(plan.fish.contains { ($0.appearsAt ?? 0) > 0 })
        #expect(scene.debugFishLeft.count == plan.fish.count)
        withExtendedLifetime(view) {}
    }

    /// The Open Water counts what you eat instead, and the tutorial counts its own.
    @Test func theOpenWaterAndTheTutorialDontShowIt() {
        let run = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        run.startOpenWater(seed: 1)
        _ = run.debugPlayOpenWater(untilLevel: 0)
        run.debugRemoveFish(max(0, run.debugFishLeft.count - 1))
        #expect(run.debugFishLeft.shown == nil)

        let tutorial = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(tutorial)
        var showed = false
        _ = tutorial.debugPlayTutorial(from: .eatEnough) { showed = showed || tutorial.debugFishLeft.shown != nil }
        #expect(!showed)
        withExtendedLifetime(view) {}
    }
}
