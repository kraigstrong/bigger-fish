import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

struct ShallowCampaignTests {
    @MainActor @Test func shallowCampaignAdvancesToTenAndReplaysItsFinale() {
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
                #expect(scene.debugResultTitles == ["Back to world", "Play again"])
                scene.debugTapResult(.playAgain)
                #expect(scene.debugLevelIndex == 9)
                #expect(scene.debugFishCount == scene.debugMeetingPlan!.fish.count + 1)
                scene.debugStart()
                scene.debugClearLevel()
                scene.debugTapResult(.world)
                #expect(exits == 1)
            } else {
                #expect(scene.debugResultTitles == ["Next level", "Play again", "Levels"])
                scene.debugTapResult(.nextLevel)
                #expect(scene.debugLevelIndex == index + 1)
                #expect(scene.debugFishCount == scene.debugMeetingPlan!.fish.count + 1)
            }
            withExtendedLifetime(view) {}
        }
    }
}
