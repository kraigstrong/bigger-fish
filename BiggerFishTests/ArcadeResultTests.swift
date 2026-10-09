import CoreGraphics
import SpriteKit
import Testing
@testable import BiggerFish

@MainActor
struct ArcadeResultTests {
    @Test func completionStopsMotionButKeepsAnimationAndResumesOnReplayOrNextLevel() {
        for world in ArcadeWorld.campaign {
            for replay in [false, true] {
                let scene = GameScene(world: world)
                let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
                view.presentScene(scene)
                #expect(scene.debugCompletionMotionCheck(replay: replay))
                withExtendedLifetime(view) {}
            }
        }
    }

    /// A world's first level-10 win skips its result card and leaves for the conquered screen; any other win
    /// shows the card.
    @Test func conqueringWinGoesStraightToTheConqueredScreen() {
        for conquers in [true, false] {
            let scene = GameScene(world: .kelpForest, levelIndex: ArcadeWorld.mainLevelCount - 1)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            var exited = false
            scene.onClear = { _, _ in scene.leavesForConqueredScreen = conquers }
            scene.onExit = { exited = true }
            scene.debugStart(); scene.debugClearLevel()
            #expect(scene.debugResultTitles.isEmpty == conquers)
            scene.debugAdvance(seconds: GameTuning.conqueredExitDelay - 0.2)
            #expect(!exited)
            scene.debugAdvance(seconds: 0.4)
            #expect(exited == conquers)
            withExtendedLifetime(view) {}
        }
    }

    @Test func readyPromptFitsTheCardAndHasNoMapAction() throws {
        for world in ArcadeWorld.campaign {
            let scene = GameScene(world: world, showsJellyLesson: true)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            let prompt = try #require(scene.childNode(withName: "//beginPrompt") as? SKLabelNode)
            let card = try #require(scene.childNode(withName: "//readyCard") as? SKShapeNode)
            #expect(prompt.text == "Tap anywhere to begin")
            #expect(prompt.fontSize >= 22 && prompt.alpha == 1)
            #expect(card.frame.contains(prompt.frame))
            #expect(!(card.parent?.children.contains { $0 is SKShapeNode && $0 !== card } ?? true))
            withExtendedLifetime(view) {}
        }
    }

    @Test func resultAccessibilityListsPrimaryFirstAndClearsOnNextLevel() {
        let scene = GameScene(world: .shallowReef)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        let window = UIWindow(frame: view.frame)
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.presentScene(scene)
        scene.debugStart(); scene.debugClearLevel()
        let elements = scene.accessibilityElements as? [ArcadeResultAccessibilityElement]
        #expect(elements?.map(\.accessibilityLabel) == ["Next level", "Play again", "Levels"])
        // CI can host this window in portrait; verify coordinate conversion independently
        // of orientation. Landscape touch-target sizing is checked below.
        let scale = min(view.bounds.width / scene.size.width, view.bounds.height / scene.size.height)
        #expect(abs((elements?.first?.accessibilityFrame.height ?? 0) - 58 * scale) < 0.5)
        scene.debugTapResult(.nextLevel)
        #expect(scene.accessibilityElements == nil)
        withExtendedLifetime(view) {}
    }

    @Test func primaryDestinationsAndTapTargetsStayDistinct() {
        for size in [CGSize(width: 667, height: 375), CGSize(width: 874, height: 402)] {
            for (passed, hasNext, expected) in [(false, true, ArcadeResultAction.tryAgain),
                                               (true, true, .nextLevel), (true, false, .world)] {
                let panel = ArcadeResultPanel(size: size, passed: passed, hasNext: hasNext, detail: "Jelly Bloom complete!")
                #expect(panel.primaryAction == expected)
                let primary = panel.controls[0].frame
                #expect(primary.width > panel.controls[1].frame.width)
                let scale = GameTuning.fittedPlayfieldSize(in: size).width / GameTuning.playfieldSize.width
                #expect(primary.height * scale >= 44)
                for control in panel.controls.dropFirst() {
                    #expect(!primary.intersects(control.frame))
                    #expect(control.frame.height * scale >= 44)
                }
                var selected: ArcadeResultAction?
                panel.onSelect = { selected = $0 }
                panel.handleTap(at: CGPoint(x: primary.midX, y: primary.midY))
                #expect(selected == expected)
                selected = nil
                panel.handleTap(at: CGPoint(x: 0, y: 83))
                #expect(selected == nil)
            }
        }
    }
}
