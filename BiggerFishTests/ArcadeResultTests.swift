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

    /// Next level onto a level past the free ones leaves for the unlock's screen instead of playing it.
    @Test func nextLevelPastTheFreeOnesLeavesForTheUnlock() {
        for locked in [true, false] {
            let scene = GameScene(world: .jellyBloom, levelIndex: 1)
            let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
            view.presentScene(scene)
            var exited = false
            scene.levelNeedsUnlock = { index in locked && index >= 2 }
            scene.onExit = { exited = true }
            scene.debugStart(); scene.debugClearLevel()
            scene.debugAdvance(seconds: 1)
            scene.debugTapResult(.nextLevel)
            #expect(exited == locked && scene.leftForUnlock == locked)
            #expect(scene.currentLevelIndex == (locked ? 1 : 2))
            withExtendedLifetime(view) {}
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
            #expect(prompt.text == "Tap to start")
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
    /// An Open Water run's card: its best-run note sits clear of the buttons, the Shop button's pearls fit on it, and
    /// VoiceOver says them.
    @Test func anOpenWaterCardsNoteAndPearlsFit() throws {
        for size in [CGSize(width: 667, height: 375), CGSize(width: 874, height: 402)] {
            let panel = ArcadeResultPanel(size: size, passed: false, hasNext: true,
                                          detail: "Stage 3 · Kelp Forest · 41 fish · 3 pearls", heading: "New best!",
                                          note: "Best: 41 fish", shopPearls: 1234)
            #expect(panel.headingText == "New best!" && panel.noteText == "Best: 41 fish")
            let note = try #require(panel.children.compactMap { $0 as? SKLabelNode }.first { $0.text == "Best: 41 fish" })
            for control in panel.controls { #expect(!note.frame.intersects(control.frame)) }
            let shop = try #require(panel.controls.first { $0.action == .shop })
            let caption = try #require(panel.children.lazy.compactMap { $0.childNode(withName: "shopCaption") }.first)
            #expect(caption.calculateAccumulatedFrame().width < shop.frame.width - 16)
            #expect(panel.spokenTitle(.shop) == "Shop, 1234 pearls" && panel.spokenTitle(.tryAgain) == "Retry")
            panel.showShopPearls(1)
            #expect(panel.shopPearls == 1 && panel.spokenTitle(.shop) == "Shop, 1 pearl")
            // A run's pearls count up into the rest; spending meanwhile shows what's left at once.
            panel.showShopPearls(12)
            panel.countShopPearls(from: 9, after: 0.5)
            #expect(panel.shownShopPearls == 9 && panel.shopPearls == 12)
            panel.showShopPearls(4)
            #expect(panel.shownShopPearls == 4 && panel.shopPearls == 4)
        }
    }
}
