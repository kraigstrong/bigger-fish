import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// A playtester didn't know beating all ten levels was the goal: every card and map shows the run and what's left.
struct WorldProgressTests {
    @Test func aWorldsRunIsItsTenLevelsThenItsDeepEnd() {
        let none = WorldProgress(world: .kelpForest, level: 3) { _ in false }
        #expect(none.run == 0..<10 && !none.isDeepEnd && none.remaining == 10)
        #expect(none.caption == "Clear all 10 to conquer Kelp Forest")

        let some = WorldProgress(world: .kelpForest, level: 3) { $0 < 3 }
        #expect(some.clearedCount == 3 && some.caption == "7 more to conquer Kelp Forest")

        let all = WorldProgress(world: .kelpForest, level: 9) { $0 < 10 }
        #expect(all.isConquered && all.caption == "Kelp Forest conquered!")

        // The Deep End is its own run, counted apart from the main levels.
        let deep = WorldProgress(world: .kelpForest, level: 11) { $0 < 11 }
        #expect(deep.run == 10..<15 && deep.isDeepEnd && deep.clearedCount == 1)
        #expect(deep.caption == "4 more to conquer The Deep End")
    }

    /// The card before a level shows the run; after a first win, its pip counts and the caption says what's left.
    @Test func theReadyAndWinCardsShowTheWorldsProgress() {
        var cleared: Set<Int> = [0, 1]
        let scene = GameScene(world: .jellyBloom, levelIndex: 2)
        scene.hasCleared = { cleared.contains($0) }
        scene.onClear = { index, _ in cleared.insert(index) }
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        #expect(scene.debugProgressCaption == "8 more to conquer Jelly Bloom")
        scene.debugStart(); scene.debugClearLevel()
        #expect(scene.debugProgressCaption == "7 more to conquer Jelly Bloom")
        withExtendedLifetime(view) {}
    }

    /// The tutorial has no world to conquer.
    @Test func theTutorialShowsNoProgress() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        #expect(scene.debugProgressCaption == nil)
        withExtendedLifetime(view) {}
    }
}
