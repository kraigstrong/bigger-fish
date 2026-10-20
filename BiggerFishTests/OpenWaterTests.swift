import CoreGraphics
import FishKit
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The Open Water, the endless run's prototype (Xcode builds only): round the worlds a stage at a time, each world a new
/// level made at that stage's difficulty, planned as the run reaches it; eat a level's last gate and you shrink back to
/// your starting size for the next; being eaten ends the run.
@MainActor
struct OpenWaterTests {
    /// A stage goes round every world at one difficulty: each world's level 5 on stage 1, level 6 on stage 2.
    @Test func aStageGoesRoundEveryWorld() {
        let worlds = GameTuning.openWaterWorlds
        #expect(worlds == ArcadeWorld.campaign)
        for (index, world) in worlds.enumerated() {
            #expect(OpenWater.leg(index) == OpenWater.Leg(stage: 1, world: world, level: 5))
            #expect(OpenWater.leg(worlds.count + index) == OpenWater.Leg(stage: 2, world: world, level: 6))
        }
    }

    /// A level is made at the settings of its world's own level of that number: speeds, sizes, margins, and the
    /// world's hazards. Past the Deep End, its five again, faster each time round, up to a limit.
    @Test func eachLevelIsMadeAtItsWorldsOwnSettings() {
        func numbers(_ spec: MeetingSpec) -> [Double] {
            [spec.crossSeconds, spec.aiSpeed.lowerBound, spec.aiSpeed.upperBound, spec.gateMargin, spec.dangerGap,
             spec.threatClearance, spec.spacing, spec.foodSize.lowerBound, spec.worldScreens, Double(spec.extraThreats)]
        }
        let shallow = GameTuning.reefLabSpecs[GameTuning.shallowReefOrder[4]]
        #expect(numbers(OpenWater.template(.shallowReef, level: 5)) == numbers(shallow))
        #expect(OpenWater.template(.jellyBloom, level: 5).jellies == GameTuning.jellyLabSpecs[4].jellies)
        #expect(OpenWater.template(.kelpForest, level: 5).kelp == GameTuning.kelpSpecs[4].kelp)
        #expect(OpenWater.template(.sunsetCove, level: 5).hooks == GameTuning.sunsetSpecs[4].hooks)
        #expect(numbers(OpenWater.template(.midnightZone, level: 6)) == numbers(GameTuning.midnightSpecs[5]))
        let deepEnd = GameTuning.kelpSpecs[10], past = OpenWater.template(.kelpForest, level: 16)
        #expect(past.segments == deepEnd.segments && past.kelp == deepEnd.kelp)
        #expect(abs(past.crossSeconds - deepEnd.crossSeconds / 1.05) < 1e-9)
        #expect(abs(past.aiSpeed.upperBound - deepEnd.aiSpeed.upperBound * 1.05) < 1e-9)
        let far = OpenWater.template(.kelpForest, level: 400)
        let farSource = GameTuning.kelpSpecs[10 + (400 - 16) % 5]
        #expect(abs(far.crossSeconds - farSource.crossSeconds / (1 + GameTuning.openWaterSpeedUpLimit)) < 1e-9)
    }

    /// A level isn't a copy of its template: its segments are dealt again, a meal either way, each gate keeping the
    /// template's slack on the short lanes and no more danger than it had.
    @Test func levelsAreNewDealsOfTheirTemplates() {
        var differ = 0, total = 0
        for seed in UInt64(1)...20 {
            for index in 0..<GameTuning.openWaterWorlds.count {
                let leg = OpenWater.leg(index), template = OpenWater.template(leg.world, level: leg.level)
                let spec = OpenWater.spec(index, seed: seed)
                total += 1
                if spec.segments != template.segments { differ += 1 }
                #expect(spec.segments.count == template.segments.count)
                #expect(spec.crossSeconds == template.crossSeconds && spec.jellies == template.jellies
                        && spec.kelp == template.kelp && spec.hooks == template.hooks)
                for (segment, base) in zip(spec.segments, template.segments) {
                    #expect((1...max(1, segment.mostMeals)).contains(segment.needed))
                    #expect(segment.dangerFoods <= base.dangerFoods)
                    #expect(segment.forks.allSatisfy { $0.long >= $0.short && $0.long <= 3 })
                    let slack = { (s: MeetingSpec.Segment) in s.singles + s.forks.reduce(0) { $0 + $1.short } - s.needed }
                    #expect(slack(segment) >= min(slack(base), slack(segment) + segment.needed - 1))
                }
            }
        }
        #expect(differ > total * 3 / 4, "only \(differ) of \(total) deals differ from their templates")
    }

    /// A run's levels plan the same every time, and another run's differently.
    @Test func aRunsSeedNamesItsLayouts() {
        let plan = OpenWater.plan(2, seed: 7)
        #expect(OpenWater.plan(2, seed: 7).fish == plan.fish)
        #expect(OpenWater.plan(2, seed: 8).fish != plan.fish)
    }

    /// Two stages' levels, every world twice, plan with nothing off (what the planner promises: placement, fit,
    /// clearances, not whether a bot could win), and each has a last gate to end it.
    @Test(arguments: [UInt64(1), 2, 3])
    func everyLevelPlansCleanly(seed: UInt64) {
        var slowest: [ArcadeWorld: Double] = [:]
        for index in 0..<(2 * GameTuning.openWaterWorlds.count) {
            let started = Date()
            let plan = OpenWater.plan(index, seed: seed)
            let world = OpenWater.leg(index).world
            slowest[world] = max(slowest[world] ?? 0, Date().timeIntervalSince(started))
            #expect(plan.issues.isEmpty, "level \(index) (\(world)): \(plan.issues)")
            #expect(!plan.hasGiantWall, "level \(index) (\(world)) has a wall of giants")
            #expect(OpenWater.finale(plan) != nil, "level \(index) (\(world)) has no gate")
            // Jelly Bloom's bells, planned just in time like the other worlds' fish.
            #expect((plan.jellies?.isEmpty == false) == (world == .jellyBloom), "level \(index) (\(world))")
            #expect(plan.fish.allSatisfy { $0.appearsAt != nil }, "level \(index) (\(world))")
        }
        print("[OpenWater] seed \(seed), slowest plan (ms): "
              + slowest.map { "\($0.key.rawValue) \(Int($0.value * 1000))" }.sorted().joined(separator: ", "))
    }

    /// Jelly Bloom's levels plan just in time like the other worlds': its bells where the designer puts them, every
    /// fish's way in clear of them, three stages deep across a handful of runs, in a few seconds at most.
    @Test func jellyLevelsPlanInTime() {
        let worlds = GameTuning.openWaterWorlds, jelly = worlds.firstIndex(of: .jellyBloom)!
        var slowest = 0.0, fewer = 0, levels = 0
        for seed in UInt64(11)...16 {
            for stage in 0..<3 {
                let index = stage * worlds.count + jelly, started = Date()
                let plan = OpenWater.plan(index, seed: seed)
                slowest = max(slowest, Date().timeIntervalSince(started))
                levels += 1
                if plan.spec.extraThreats < OpenWater.spec(index, seed: seed).extraThreats { fewer += 1 }
                #expect(plan.issues.isEmpty && !plan.hasGiantWall, "seed \(seed), stage \(stage + 1): \(plan.issues)")
                #expect(plan.jellies?.isEmpty == false)
            }
        }
        print("[OpenWater] Jelly Bloom: slowest plan \(Int(slowest * 1000)) ms, \(fewer) of \(levels) with one fewer big fish")
    }

    /// Pearls sit beside danger, a few a level: each just outside a big fish's body where you pass it, never on top
    /// of it, and most levels have some.
    @Test func pearlsSitBesideDanger() {
        var levels = 0, withPearls = 0
        for seed in UInt64(1)...3 {
            for index in 0..<(2 * GameTuning.openWaterWorlds.count) {
                let plan = OpenWater.plan(index, seed: seed), pearls = OpenWater.pearls(plan)
                let world = WrappedWorld(width: GameTuning.playfieldSize.width * CGFloat(plan.spec.worldScreens))
                levels += 1
                if !pearls.isEmpty { withPearls += 1 }
                #expect(pearls.count <= GameTuning.openWaterPearlsPerLevel)
                let threats = Set(plan.fish.filter { $0.role == .threat }.map(\.id))
                for pearl in pearls {
                    let beside = plan.predicted.contains { crossing in
                        let off = abs(CGFloat(crossing.y) - pearl.position.y), r = CGFloat(crossing.radius)
                        return threats.contains(crossing.fishID)
                            && abs(world.delta(from: CGFloat(crossing.distance), to: pearl.position.x)) < 1
                            && off > r * GameTuning.collisionScale && off < 3 * r + 3 * GameTuning.openWaterPearlGap
                    }
                    #expect(beside, "level \(index), seed \(seed): a pearl at \(pearl.position) beside no big fish")
                }
            }
        }
        #expect(withPearls * 4 >= levels * 3, "only \(withPearls) of \(levels) levels have pearls")
        print("[OpenWater] pearls on \(withPearls) of \(levels) levels")
    }

    /// Touching a pearl takes it: it counts, and it doesn't grow you.
    @Test func takingAPearlCountsItWithoutGrowingYou() throws {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.debugStartOpenWater(seed: 1)
        _ = scene.debugPlayOpenWater(untilLevel: 0)
        let count = scene.debugOpenWaterPearls.count
        let taken = try #require(scene.debugTakeFirstPearl())
        #expect(taken.pearls == 1 && taken.after == taken.before)
        #expect(scene.debugOpenWaterPearls.count == count - 1)
        scene.debugLose()
        #expect(scene.debugResultDetail?.hasSuffix("· 1 pearl") == true)
    }

    /// Each level ends once you eat its last gate, and the next world's begins the way a level does: you at your
    /// starting size with the camera all the way in, at the start of its lap and its clock, every fish its plan has
    /// on its way, and the world's own hazards. Nothing is ever won or cleared.
    @Test func eachLevelEndsOnItsLastGateAndStartsYouSmall() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.debugStartOpenWater(seed: 1)
        var cleared = false
        scene.onClear = { _, _ in cleared = true }
        let worlds = GameTuning.openWaterWorlds
        let run = scene.debugPlayOpenWater(untilLevel: worlds.count + 1, safeFromFish: true)
        #expect(run.index == worlds.count + 1 && !run.lost && !run.won && !cleared, "stopped at level \(run.index): \(run.reason)")
        #expect(run.starts.map(\.world) == worlds + [worlds[0], worlds[1]])
        for start in run.starts {
            let name = "level \(start.index) (\(start.world))"
            #expect(start.radius == GameTuning.baseRadius && start.zoom == 1, "\(name)")
            #expect(start.forwardDistance == 0 && start.clock == 0, "\(name)")
            #expect(start.fish == start.planned && start.planned > 0, "\(name)")
            #expect((start.jellies > 0) == (start.world == .jellyBloom), "\(name)")
            #expect((start.kelp > 0) == (start.world == .kelpForest), "\(name)")
            #expect((start.hooks > 0) == (start.world == .sunsetCove), "\(name)")
            #expect(start.dark == (start.world == .midnightZone), "\(name)")
        }
        #expect(run.largest > GameTuning.baseRadius * 1.5)
    }

    /// Being eaten ends the run, and its result says how far it got. Retry starts a new run, the next seed on, back
    /// at the first world.
    @Test func beingEatenEndsTheRun() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false)
        scene.debugStartOpenWater(seed: 5)
        #expect(scene.debugPlayOpenWater(untilLevel: 1, safeFromFish: true).index == 1)
        #expect(scene.arcadeWorld == GameTuning.openWaterWorlds[1])
        scene.debugLose()
        #expect(scene.debugResultDetail?.hasPrefix("Stage 1 · \(GameTuning.openWaterWorlds[1].title) · ") == true)
        scene.debugTapResult(.tryAgain)
        #expect(scene.debugOpenWaterIndex == 0 && scene.debugOpenWaterSeed == 6)
        #expect(scene.arcadeWorld == GameTuning.openWaterWorlds[0])
    }
}
