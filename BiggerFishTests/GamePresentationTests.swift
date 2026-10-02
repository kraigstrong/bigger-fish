import CoreGraphics
import FishKit
import Testing
@testable import BiggerFish

struct GamePresentationTests {
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
        let scene = GameScene(size: CGSize(width: 874, height: 402), world: .jellyBloom)
        #expect(scene.debugCheckPresentationIsolation())
    }
}
