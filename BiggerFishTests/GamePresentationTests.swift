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
            frameRemainder: 0, timeScale: 0.35, lag: step, step: step)
        let nextDisplay = PresentationInterpolation.fraction(simulationRemainder: step * 0.35,
            frameRemainder: step / 2, timeScale: 0.35, lag: step, step: step)
        #expect(abs(first - 0.35) < 1e-10)
        #expect(abs(nextDisplay - 0.525) < 1e-10)
        #expect(nextDisplay > first)
    }

    @MainActor @Test func renderingBetweenTicksDoesNotAdvanceGameplayAndPauseClearsHistory() {
        let scene = GameScene(world: .jellyBloom)
        #expect(scene.debugCheckPresentationIsolation())
    }

    @MainActor @Test func fixedGameplayRepeatsAcrossDisplaySchedulesIncludingSlowMotion() {
        let schedules = [
            Array(repeating: CGFloat(1) / 60, count: 480),
            Array(repeating: CGFloat(1) / 30, count: 240),
            Array(repeating: CGFloat(1) / 120, count: 960),
            (0..<480).map { CGFloat($0.isMultiple(of: 2) ? 1 : 3) / 120 },
            Array(repeating: CGFloat(1) / 10, count: 80),
        ]
        for slow in [false, true] {
            func run(_ frames: [CGFloat]) -> ArcadeSimulation.Audit {
                let scene = GameScene(world: .jellyBloom, levelIndex: 4)
                return scene.debugAuditRepeatability(frames: frames, fixedStep: true,
                    slowMotion: slow, scriptedInput: true)
            }
            let control = run(schedules[0])
            for schedule in schedules.dropFirst() { #expect(control == run(schedule)) }
        }
    }

    @MainActor @Test func aSixtyHertzDisplayDrawsATouchOnTheFrameItLands() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        #expect(scene.debugTouchToDrawSeconds(frameInterval: 1.0 / 60) == 0)
        // 120 Hz blends between steps as it always has: a touch starts to show a frame or two later.
        #expect(abs(scene.debugTouchToDrawSeconds(frameInterval: 1.0 / 120) - 0.0125) < 1e-9)
    }

    @MainActor @Test func drawingKeepsAnEvenPaceAndNeverRunsBackward() {
        // 60 Hz with a couple of milliseconds of timestamp jitter, a close call at frame 60, two dropped frames at
        // 150, 120 Hz from 200 to 300, then jittery 60 Hz again.
        let step = 1.0 / 60
        var times: [Double] = []
        var time = 1_000.0
        for frame in 0..<420 {
            let jitter = frame < 60 || frame >= 300 ? 0.002 * sin(Double(frame) * 1.7) : 0
            times.append(time + jitter)
            time += frame == 150 ? 3 * step : (200..<300).contains(frame) ? step / 2 : step
        }
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let moments = scene.debugDrawnMoments(at: times, slowMotionAt: 60)
        let advances = zip(moments.dropFirst(), moments).map { ($0 - $1) / step }
        func advance(_ frame: Int) -> Double { advances[frame - 1] }
        for frame in 1..<moments.count {
            // At most a quarter step past the frame's own time (or a step's, for a frame that came early).
            let elapsed = max((times[frame] - times[frame - 1]) / step, 1)
            #expect(advance(frame) >= -1e-9, "frame \(frame) drew an earlier moment")
            #expect(advance(frame) <= elapsed * 1.25 + 1e-9, "frame \(frame) jumped")
        }
        // Each 60 Hz frame takes and draws exactly one step, jitter and all; 120 Hz frames draw half a step.
        for frame in Array(20..<60) + Array(320..<420) { #expect(abs(advance(frame) - 1) < 1e-9, "frame \(frame)") }
        for frame in 220..<300 { #expect(abs(advance(frame) - 0.5) < 1e-9, "frame \(frame)") }
        // Slow motion holds for the moment it needs to have a step to draw, then keeps a steady pace.
        for frame in 63..<88 { #expect((0.2...0.5).contains(advance(frame)), "frame \(frame)") }
    }

    @MainActor @Test func fixedTimingBoundsHitchesAndDropsPausedDebt() {
        let scene = GameScene(world: .jellyBloom)
        #expect(scene.debugCheckFixedTimingLifecycle())
    }
}
