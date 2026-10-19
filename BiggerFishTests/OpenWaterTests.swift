import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The Open Water, the endless run's prototype (Xcode builds only): stages planned as the run reaches them, a size
/// reset between them, and a run that ends when you're eaten.
@MainActor
struct OpenWaterTests {
    /// Stages step through Shallow Reef's levels in play order, then its Deep End again and again, a little faster
    /// each time round.
    @Test func stagesRampThroughShallowReefThenLoopTheDeepEnd() {
        let specs = GameTuning.reefLabSpecs
        for (index, source) in GameTuning.openWaterRamp.enumerated() {
            let spec = OpenWater.spec(stage: index + 1)
            #expect(spec.segments == specs[source].segments && spec.crossSeconds == specs[source].crossSeconds)
        }
        let first = OpenWater.spec(stage: GameTuning.openWaterRamp.count + 1)
        let deepEnd = specs[GameTuning.openWaterLoop[0]]
        #expect(first.segments == deepEnd.segments)
        #expect(abs(first.crossSeconds - deepEnd.crossSeconds / 1.05) < 1e-9)
        #expect(abs(first.aiSpeed.upperBound - deepEnd.aiSpeed.upperBound * 1.05) < 1e-9)
        // Far on, the speed-up stops growing.
        let far = OpenWater.spec(stage: 400)
        let farSource = specs[GameTuning.openWaterLoop[(400 - 1 - GameTuning.openWaterRamp.count) % GameTuning.openWaterLoop.count]]
        #expect(abs(far.crossSeconds - farSource.crossSeconds / (1 + GameTuning.openWaterSpeedUpLimit)) < 1e-9)
    }

    /// A run's stages plan the same every time, and another run's differently.
    @Test func aRunsSeedNamesItsLayouts() {
        let plan = OpenWater.plan(stage: 3, seed: 7)
        #expect(OpenWater.plan(stage: 3, seed: 7).fish == plan.fish)
        #expect(OpenWater.plan(stage: 3, seed: 8).fish != plan.fish)
    }

    /// A stage ends when you come round to its start, and the next begins the way a level does: you at your starting
    /// size with the camera all the way in, at the start of its lap and its clock, every fish its plan has on its way.
    /// The run goes on, and nothing is ever won or cleared.
    @Test func eachStageStartsYouSmallAgain() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.debugStartOpenWater(seed: 1)
        var cleared = false
        scene.onClear = { _, _ in cleared = true }
        let run = scene.debugPlayOpenWater(untilStage: 4, safeFromFish: true)
        #expect(run.stage == 4 && !run.lost && !run.won && !cleared)
        #expect(run.starts.map(\.stage) == [1, 2, 3, 4])
        for start in run.starts {
            #expect(start.radius == GameTuning.baseRadius && start.zoom == 1, "stage \(start.stage)")
            #expect(start.forwardDistance == 0 && start.clock == 0, "stage \(start.stage)")
            #expect(start.fish == start.planned && start.planned > 0, "stage \(start.stage)")
        }
        // Each stage is its own level's lap.
        #expect(run.starts[1].worldWidth == GameTuning.playfieldSize.width * CGFloat(OpenWater.spec(stage: 2).worldScreens))
        // You grew in between, so the reset had something to undo.
        #expect(run.largest > GameTuning.baseRadius * 1.5)
    }

    /// Being eaten ends the run, and its result says how far it got. Retry starts a new run, the next seed on, from
    /// its first stage.
    @Test func beingEatenEndsTheRun() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.debugStartOpenWater(seed: 5)
        #expect(scene.debugPlayOpenWater(untilStage: 2, safeFromFish: true).stage == 2)
        scene.debugLose()
        #expect(scene.debugResultDetail?.hasPrefix("Stage 2 · ") == true)
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugOpenWaterStage == 1 && scene.debugOpenWaterSeed == 6)
    }

    /// Every stage of the ramp and the first time round the loop plans with nothing off: what the planner promises
    /// (placement, fit, clearances), not whether a bot could win it.
    @Test(arguments: [UInt64(1), 2, 3])
    func everyStagePlansCleanly(seed: UInt64) {
        let stages = GameTuning.openWaterRamp.count + GameTuning.openWaterLoop.count
        var slowest = 0.0
        for stage in 1...stages {
            let started = Date()
            let plan = OpenWater.plan(stage: stage, seed: seed)
            slowest = max(slowest, Date().timeIntervalSince(started))
            #expect(plan.issues.isEmpty, "stage \(stage): \(plan.issues)")
            #expect(!plan.hasGiantWall, "stage \(stage) has a wall of giants")
        }
        print("[OpenWater] seed \(seed): slowest stage planned in \(Int(slowest * 1000)) ms")
    }
}
