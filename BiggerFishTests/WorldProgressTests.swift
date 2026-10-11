import Foundation
import SpriteKit
import Testing
import UIKit
@testable import BiggerFish

/// A playtester didn't know beating all ten levels was the goal: every card and map shows the run and what's left.
@MainActor
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

    /// Crowns go silver, then gold, as Math Reef's do: silver for a world's ten levels, gold once its Deep End is beaten.
    @Test func aWorldsCrownIsSilverThenGold() {
        #expect(WorldCrown.earned(conquered: false, deepEndCleared: false) == .none)
        #expect(WorldCrown.earned(conquered: true, deepEndCleared: false) == .silver)
        #expect(WorldCrown.earned(conquered: true, deepEndCleared: true) == .gold)
        #expect(WorldCrown.none.color == nil && WorldCrown.silver.color == DeepEndColors.silver && WorldCrown.gold.color == DeepEndColors.gold)
        // Each run's own crown: the main levels earn silver, the Deep End gold.
        #expect(WorldProgress(world: .jellyBloom, level: 4) { _ in true }.crown == .silver)
        #expect(WorldProgress(world: .jellyBloom, level: 12) { _ in true }.crown == .gold)
    }

    /// The card before a level shows the run's pips; after a first win, its pip counts and the caption says what's left.
    @Test func theReadyAndWinCardsShowTheWorldsProgress() {
        var cleared: Set<Int> = [0, 1]
        let scene = GameScene(world: .jellyBloom, levelIndex: 2)
        scene.hasCleared = { cleared.contains($0) }
        scene.onClear = { index, _ in cleared.insert(index) }
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        #expect(scene.debugProgressCaption == "")
        scene.debugStart(); scene.debugClearLevel()
        #expect(scene.debugProgressCaption == "7 more to conquer Jelly Bloom")
        withExtendedLifetime(view) {}
    }

    /// A playtester found the card before each level too wordy: it's the level, its pips, and "Tap to start". A world's
    /// first level also says what's new in it, until it's beaten; playing a level again skips the card.
    @Test func theCardBeforeALevelIsShort() {
        func card(_ world: ArcadeWorld, _ index: Int, cleared: Set<Int>) -> [String] {
            let scene = GameScene(world: world, levelIndex: index)
            scene.hasCleared = { cleared.contains($0) }
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            defer { withExtendedLifetime(view) {} }
            return scene.debugCardTexts
        }
        #expect(card(.kelpForest, 0, cleared: []) == ["Level 1"] + ArcadeWorld.kelpForest.rules + ["Tap to start"])
        #expect(card(.kelpForest, 0, cleared: [0]) == ["Level 1", "Tap to start"])
        #expect(card(.kelpForest, 3, cleared: [0, 1, 2]) == ["Level 4", "Tap to start"])
        // Shallow Reef has nothing new to say: the tutorial taught it all.
        #expect(card(.shallowReef, 0, cleared: []) == ["Level 1", "Tap to start"])

        // Lose, Retry: straight back in, with just the prompt; the next level gets its card again.
        let scene = GameScene(world: .jellyBloom, levelIndex: 1)
        scene.hasCleared = { $0 == 0 }
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart(); scene.debugLose()
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugCardTexts == ["Tap to start"] && scene.debugProgressCaption == nil)
        scene.debugStart(); scene.debugClearLevel()
        scene.debugAdvance(seconds: 1)
        scene.debugTapResult(.nextLevel)
        #expect(scene.debugCardTexts == ["Level 3", "Tap to start"])
        withExtendedLifetime(view) {}
    }

    /// Restart from the pause menu replays without the card, whether it's tapped or chosen with VoiceOver.
    @Test func voiceOverRestartAlsoSkipsTheCard() {
        let scene = GameScene(world: .kelpForest, levelIndex: 2)
        scene.hasCleared = { $0 < 2 }
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        scene.debugPauseForTuning()
        let restart = (scene.accessibilityElements as? [UIAccessibilityElement])?.first { $0.accessibilityLabel == "Restart" }
        #expect(restart?.accessibilityActivate() == true)
        #expect(scene.debugCardTexts == ["Tap to start"])
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
