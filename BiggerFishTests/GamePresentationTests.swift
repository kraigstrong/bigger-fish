import CoreGraphics
import FishKit
import SpriteKit
import Testing
@testable import BiggerFish

struct GamePresentationTests {
    @Test func playfieldFitsUniformlyWithoutCropping() {
        for display in [CGSize(width: 874, height: 402), CGSize(width: 667, height: 375),
                        CGSize(width: 1194, height: 834), CGSize(width: 402, height: 874)] {
            let fitted = GameTuning.fittedPlayfieldSize(in: display)
            #expect(fitted.width <= display.width)
            #expect(fitted.height <= display.height)
            #expect(abs(fitted.width / fitted.height - 874.0 / 402.0) < 1e-10)
            #expect(abs(fitted.width - display.width) < 1e-8 || abs(fitted.height - display.height) < 1e-8)
        }
    }

    @MainActor @Test func differentDisplaysAndResizingPreserveTheSameGameplay() {
        let frames = Array(repeating: CGFloat(1) / 60, count: 240)
        func run(display: CGSize, resize: Bool) -> ArcadeSimulation.Audit {
            let scene = GameScene(world: .jellyBloom, levelIndex: 6)
            let view = SKView(frame: CGRect(origin: .zero, size: display))
            view.presentScene(scene)
            view.isPaused = true
            #expect(scene.scaleMode == .aspectFit)
            #expect(scene.size == GameTuning.playfieldSize)
            let audit = scene.debugAuditRepeatability(frames: frames, fixedStep: true, scriptedInput: true)
            if resize {
                view.frame.size = CGSize(width: 1194, height: 834)
                view.layoutIfNeeded()
                #expect(scene.size == GameTuning.playfieldSize)
                #expect(scene.debugGameplayClock == audit.seconds)
            }
            withExtendedLifetime(view) {}
            return audit
        }
        let control = run(display: GameTuning.playfieldSize, resize: false)
        for display in [CGSize(width: 667, height: 375), CGSize(width: 852, height: 393), CGSize(width: 1194, height: 834)] {
            #expect(run(display: display, resize: true) == control)
        }
    }

    @Test func interpolationTakesTheShortRouteAcrossTheWorldSeam() {
        let world = WrappedWorld(width: 100)
        let forward = PresentationInterpolation.position(from: CGPoint(x: 98, y: 10),
            to: CGPoint(x: 2, y: 20), fraction: 0.5, world: world)
        let backward = PresentationInterpolation.position(from: CGPoint(x: 2, y: 20),
            to: CGPoint(x: 98, y: 10), fraction: 0.5, world: world)
        #expect(forward == CGPoint(x: 0, y: 15))
        #expect(backward == forward)
    }

    @Test func swallowingAndGrowthBlendWithoutChangingTheLiveFish() {
        let fish = Fish(id: 1, isPlayer: true, position: .zero, radius: 16)
        let previous = FishPresentation(fish)
        fish.position = CGPoint(x: 10, y: 20)
        fish.radius = 24
        fish.mouth = 1
        fish.shrink = 0.2
        let pose = previous.interpolated(to: FishPresentation(fish), fraction: 0.5, world: WrappedWorld(width: 100))
        #expect(pose.position == CGPoint(x: 5, y: 10))
        #expect(pose.radius == 20)
        #expect(pose.mouth == 0.5)
        #expect(abs(pose.shrink - 0.6) < 1e-10)
        #expect(fish.position == CGPoint(x: 10, y: 20))
        #expect(fish.radius == 24)
        #expect(fish.mouth == 1)
        #expect(fish.shrink == 0.2)
    }

    @Test func slowMotionStillAdvancesThePoseBetweenRealTimeTicks() {
        let step = GameTuning.simulationStep
        let first = PresentationInterpolation.fraction(simulationRemainder: step * 0.35,
            frameRemainder: 0, timeScale: 0.35, step: step)
        let nextDisplay = PresentationInterpolation.fraction(simulationRemainder: step * 0.35,
            frameRemainder: step / 2, timeScale: 0.35, step: step)
        #expect(abs(first - 0.35) < 1e-10)
        #expect(abs(nextDisplay - 0.525) < 1e-10)
        #expect(nextDisplay > first)
    }

    @MainActor @Test func renderingBetweenTicksDoesNotAdvanceGameplayAndPauseClearsHistory() {
        let scene = GameScene(world: .jellyBloom)
        #expect(scene.debugCheckPresentationIsolation())
    }
}
