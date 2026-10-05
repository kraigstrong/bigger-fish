import CoreGraphics
import SpriteKit
import Testing
@testable import BiggerFish

@MainActor
struct ArcadeResultTests {
    @Test func readyPromptFitsTheCardAndHasNoMapAction() throws {
        for world in ArcadeWorld.allCases {
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
        #expect(elements?.first?.accessibilityFrame.height ?? 0 >= 44)
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
                #expect(primary.height >= 44)
                for control in panel.controls.dropFirst() {
                    #expect(!primary.intersects(control.frame))
                    #expect(control.frame.height >= 44)
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
